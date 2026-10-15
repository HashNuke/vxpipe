defmodule Vxpipe.Gateway.Telephony.OutgoingLegTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Dial, EndLeg, Event, LegReference, OutboundLegRequest}

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    ConfiguredService,
    DialSupervisor,
    LegSupervisor,
    MediaAdmission,
    OutgoingLeg,
    OutgoingLegConnector,
    OutgoingLegReference,
    ServiceRegistry
  }

  setup do
    media_admission = start_supervised!({MediaAdmission, name: nil})
    leg_id = "outgoing-#{System.unique_integer([:positive, :monotonic])}"

    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    %{leg_id: leg_id, media_admission: media_admission}
  end

  for command <- [:dial, :end] do
    test "#{command} command installs the owner's completion monitor before carrier effects",
         context do
      kind = unquote(command)
      service = service(self(), [])

      service = %{
        service
        | adapter_options: Keyword.put(service.adapter_options, :probe_owner_monitors, self())
      }

      result = start_probe_command(kind, service, context.leg_id)

      observer =
        case result do
          {:ok, pid} -> pid
          {:ok, pid, _monitor} -> pid
        end

      assert_receive {:command_owner_monitors, ^kind, monitors}
      assert {:process, observer} in monitors
      assert {:ok, ^observer, monitor} = result
      assert_receive {:DOWN, ^monitor, :process, ^observer, :normal}
    end
  end

  for purpose <- [:initial, :transfer] do
    test "#{purpose} cancellation retains the owner until authenticated carrier termination",
         context do
      request = %{
        request()
        | purpose: unquote(purpose),
          room_owner: self(),
          attempt_id: make_ref()
      }

      assert {:ok, leg} =
               LegSupervisor.start_outgoing(
                 LegSupervisor,
                 context.leg_id,
                 request,
                 service(self(), []),
                 context.media_admission
               )

      assert :ok = OutgoingLeg.await(leg, 1_000)
      monitor = Process.monitor(leg)
      assert :ok = OutgoingLeg.disconnect(leg, 1_000)
      assert_receive {:test_telephony_end_leg, request}
      assert request.leg.provider_call_control_id == "outbound-call-control"
      assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
      assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    end
  end

  test "a transfer connector timeout retains a pending dial for late cancellation", context do
    observer = self()

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self(), api_key: "blocked:#{:erlang.pid_to_list(self())}")]
      )

    options = [
      leg_id: fn -> context.leg_id end,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    start_supervised!(
      {Task,
       fn ->
         send(
           observer,
           {:transfer_result, OutgoingLegConnector.connect(options, request(), 100)}
         )
       end}
    )

    assert_receive {:test_telephony_dial_pending, worker}, 1_000
    on_exit(fn -> send(worker, :release_test_telephony_dial) end)
    assert_receive {:transfer_result, {:error, :outbound_connection_unavailable}}, 1_000
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(context.leg_id)
    monitor = Process.monitor(leg)
    send(worker, :release_test_telephony_dial)
    assert_receive {:test_telephony_end_leg, %EndLeg{reason: :transfer_cancelled}}, 1_000
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert_receive {:test_telephony_dial, _}
    refute_receive {:test_telephony_dial, _}
  end

  test "late answer queues cleanup after the in-flight end and owner waits for its worker",
       context do
    leg =
      start_accepted_leg(
        context,
        service(self(), api_key: "blocked-end:#{:erlang.pid_to_list(self())}")
      )

    monitor = Process.monitor(leg)
    assert :ok = OutgoingLeg.disconnect(leg, 1_000)
    assert_receive {:test_telephony_end_pending, first}
    on_exit(fn -> send(first, :reject_test_telephony_end) end)
    assert :ok = OutgoingLeg.dispatch(leg, lifecycle_event(:answered, []), 1_000)
    send(first, :reject_test_telephony_end)
    assert_receive {:test_telephony_end_pending, second}
    on_exit(fn -> send(second, :accept_test_telephony_end) end)
    second_monitor = Process.monitor(second)
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
    send(second, :accept_test_telephony_end)
    assert_receive {:DOWN, ^second_monitor, :process, ^second, :normal}
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
  end

  test "carrier termination while dial is pending drains that command before owner retirement",
       context do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service(self(), api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               context.media_admission
             )

    assert_receive {:test_telephony_dial_pending, worker}
    on_exit(fn -> send(worker, :release_test_telephony_dial) end)
    monitor = Process.monitor(leg)
    event = %{outgoing_event(context.leg_id) | kind: :ended, end_reason: :hangup}
    assert :ok = OutgoingLeg.dispatch(leg, event, 1_000)
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
    send(worker, :release_test_telephony_dial)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _}
  end

  test "an abnormal command observer death cannot prove its blocked operation drained", context do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service(self(), api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               context.media_admission
             )

    assert_receive {:test_telephony_dial_pending, operation}
    on_exit(fn -> Process.exit(operation, :kill) end)
    {watcher, _} = :sys.get_state(leg).dial_worker
    watcher_monitor = Process.monitor(watcher)
    Process.exit(watcher, :kill)
    assert_receive {:DOWN, ^watcher_monitor, :process, ^watcher, :killed}
    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    event = %{outgoing_event(context.leg_id) | kind: :ended, end_reason: :hangup}
    assert :ok = OutgoingLeg.dispatch(leg, event, 1_000)
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
    assert :ok = OutgoingLeg.disconnect(leg, 1_000)
  end

  test "unknown retirement waits for a pending command and is retained until it drains",
       context do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service(self(), api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               context.media_admission
             )

    assert_receive {:test_telephony_dial_pending, operation}
    on_exit(fn -> send(operation, :release_test_telephony_dial_unknown) end)
    monitor = Process.monitor(leg)
    assert :ok = OutgoingLeg.disconnect(leg, 1_000)
    # Deliver the owner's retention-deadline event while the command remains in flight.
    send(leg, :retire_unknown)
    _ = :sys.get_state(leg)
    send(operation, :release_test_telephony_dial_unknown)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    refute_receive {:test_telephony_end_leg, _}
  end

  test "late callback cannot replace the original control identity retained from submission",
       context do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service(self(), api_key: "control-only:#{:erlang.pid_to_list(self())}"),
               context.media_admission
             )

    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    assert :ok = OutgoingLeg.disconnect(leg, 1_000)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{leg: %{provider_call_control_id: "outbound-call-control"}}}

    wrong = %{outgoing_event(context.leg_id) | provider_call_control_id: "another-control"}
    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, wrong, 1_000)
    monitor = Process.monitor(leg)
    ended = %{outgoing_event(context.leg_id) | kind: :ended, end_reason: :hangup}
    assert :ok = OutgoingLeg.dispatch(leg, ended, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
  end

  test "an initial submission timeout preserves its owner for late acceptance and cleanup",
       context do
    observer = self()

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self(), api_key: "blocked:#{:erlang.pid_to_list(self())}")]
      )

    options = [
      leg_id: fn -> context.leg_id end,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    start_supervised!(
      {Task,
       fn ->
         send(
           observer,
           {:initial_submission_result, OutgoingLegConnector.connect(options, request, 100)}
         )
       end}
    )

    assert_receive {:test_telephony_dial_pending, leg}, 1_000
    monitor = Process.monitor(leg)
    assert_receive {:initial_submission_result, {:ok, reference, :unknown}}, 1_000
    assert :ok = OutgoingLegConnector.disconnect(options, reference)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}, 20
    send(leg, :release_test_telephony_dial)
    assert_receive {:test_telephony_end_leg, %EndLeg{reason: :call_cancelled}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert_receive {:test_telephony_dial, _}
    refute_receive {:test_telephony_dial, _}, 20
  end

  test "an initial leg without structural room ownership is rejected before dial", context do
    request = %{request() | purpose: :initial}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), []),
               context.media_admission
             )

    assert {:error, :invalid_outbound_telephony_request} = OutgoingLeg.await(leg, 1_000)
    refute_receive {:test_telephony_dial, _}, 20
  end

  test "an initial leg reports only matching authenticated outcomes to its exact room attempt",
       context do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}
    service = service(self(), [])

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    token = request.attempt_id
    mismatch = %{ended_event(:busy) | provider_call_control_id: "other"}
    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, mismatch, 1_000)
    refute_receive {:vxpipe_outbound_leg, ^token, _, _}, 20
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:busy), 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, {:ended, :busy}}, 1_000
    refute_receive {:vxpipe_outbound_leg, ^token, _, _}, 20
  end

  test "an initial leg reports an answer without media or transfer acceptance", context do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), []),
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    token = request.attempt_id
    event = lifecycle_event(:answered, [])
    assert :ok = OutgoingLeg.dispatch(leg, event, 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
    assert :ok = OutgoingLeg.dispatch(leg, event, 1_000)
    refute_receive {:vxpipe_outbound_leg, ^token, _, :answered}, 20
  end

  test "the initial connector preserves an unknown submission result", context do
    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self(), api_key: "unknown:#{:erlang.pid_to_list(self())}")]
      )

    options = [
      leg_id: fn -> context.leg_id end,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, %OutgoingLegReference{}, :unknown} =
             OutgoingLegConnector.connect(options, request, 1_000)

    assert_receive {:test_telephony_dial, _}
    refute_receive {:test_telephony_dial, _}, 20
  end

  test "room loss while ringing hangs up the exact initial leg once", context do
    room = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})
    request = %{request() | purpose: :initial, room_owner: room, attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), []),
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    monitor = Process.monitor(leg)
    send(room, :stop)
    assert_receive {:test_telephony_end_leg, %EndLeg{reason: :call_cancelled}}, 1_000
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    refute_receive {:test_telephony_end_leg, _}, 20
  end

  test "a late identity after abandoned unknown submission is cancelled without another dial",
       context do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), api_key: "unknown:#{:erlang.pid_to_list(self())}"),
               context.media_admission
             )

    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    assert :ok = OutgoingLeg.disconnect(leg, 1_000)
    monitor = Process.monitor(leg)
    assert :ok = OutgoingLeg.dispatch(leg, outgoing_event(context.leg_id), 1_000)
    assert_receive {:test_telephony_end_leg, %EndLeg{reason: :call_cancelled}}, 1_000
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert_receive {:test_telephony_dial, _}
    refute_receive {:test_telephony_dial, _}, 20
  end

  test "submits one dial and binds accepted provider identity to the exact leg", context do
    service = service(self(), answering_machine_detection: :detect)
    request = request()

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert {:ok, ^leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)

    assert_receive {:test_telephony_dial, dial}
    refute_receive {:test_telephony_dial, _duplicate}

    assert dial.leg_id == context.leg_id
    assert dial.from == "+15550001000"
    assert dial.to == "+15550001001"
    assert dial.answering_machine_detection == :detect

    assert dial.callback_url ==
             "https://voice.example.test/voice/webhooks/tenants/tenantkey1234567/telnyx"

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url, service)
    assert binding.leg == leg
    assert binding.client_state_leg_id == context.leg_id
    assert binding.tenant_id == request.tenant_id
    assert binding.call_id == request.call_id
    assert binding.room_id == request.room_id
    assert binding.incarnation_id == request.incarnation_id
    assert binding.participant_id == request.participant_id
    assert binding.provider_call_control_id == "outbound-call-control"
    assert binding.provider_call_leg_id == "outbound-call-leg"
    assert binding.provider_call_session_id == "outbound-call-session"
  end

  test "configured initial machine detection holds media and reports machine before a definitive answer",
       context do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), answering_machine_detection: :detect),
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    token = request.attempt_id
    assert :ok = OutgoingLeg.dispatch(leg, lifecycle_event(:answered, []), 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :connected}, 1_000
    refute_receive {:vxpipe_outbound_leg, ^token, _, :answered}, 20
    started = lifecycle_event(:media_started, stream_id: "stream-machine")
    assert :ok = OutgoingLeg.dispatch(leg, started, 1_000)

    assert {:error, :media_session_not_found} =
             Vxpipe.Gateway.Telephony.MediaSupervisor.snapshot(context.leg_id)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:machine), 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, {:ended, :machine}}, 1_000
    assert_receive {:test_telephony_end_leg, %EndLeg{reason: :answering_machine}}, 1_000
    refute_receive {:vxpipe_outbound_leg, ^token, _, :answered}, 20
  end

  test "unknown initial machine detection permits an answered call without claiming human proof",
       context do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service(self(), answering_machine_detection: :detect),
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    token = request.attempt_id
    assert :ok = OutgoingLeg.dispatch(leg, lifecycle_event(:answered, []), 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :connected}, 1_000
    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:unknown), 1_000)
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
  end

  test "initial media joins the outgoing callee normally and DTMF needs no transfer acceptance",
       context do
    alias Vxpipe.CallEngine
    alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}
    alias Vxpipe.Gateway.{TestTelephonySocket, Telephony.MediaSupervisor}
    id = System.unique_integer([:positive, :monotonic])

    assert {:ok, spec} =
             CallSpec.new(
               %{
                 schema_version: CallSpec.schema_version(),
                 outgoing_call: %{
                   callee: "customer",
                   handled_by: "assistant",
                   ring_timeout_ms: 5_000
                 },
                 defaults: %{
                   capabilities: %{
                     model_inference: %{provider: "fixture", model: "google:test-model"}
                   }
                 },
                 wait_sounds: nil,
                 call_variables: %{sections: %{}},
                 participants: %{
                   "customer" => %{
                     type: "human",
                     connection: %{
                       service: "telnyx-primary",
                       mode: "dial",
                       number: "+15550001001"
                     }
                   },
                   "assistant" => %{
                     type: "agent",
                     prompt: "Help.",
                     first_message: %{mode: "wait_for_input"},
                     tools: %{},
                     transfers: []
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "initial-media",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "initial-media", revision: 1},
                 transport: %{type: "telephony"},
                 initial_variables: %{}
               },
               tenant_id: "tenantkey1234567",
               actor_id: "actor-initial",
               call_id: "call-initial-#{id}",
               room_id: "room-initial-#{id}"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self())]
      )

    plan = Vxpipe.Gateway.TestTelephonyServiceRepository.pin_plan(plan, service_options(self()))

    assert {:ok, room} =
             CallEngine.start_call(plan,
               outbound_leg_connector:
                 {OutgoingLegConnector,
                  [
                    leg_id: fn -> context.leg_id end,
                    media_admission: context.media_admission,
                    service_registry: registry
                  ]}
             )

    assert_receive {:test_telephony_dial, dial}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(context.leg_id)
    assert :ok = OutgoingLeg.await(leg, 1_000)

    assert {:ok, binding} =
             consume_media(context.media_admission, dial.media_url, service(self(), []))

    socket = start_supervised!({TestTelephonySocket, observer: self()})
    assert :ok = TestTelephonySocket.bind_readiness(socket, binding, "stream-initial")

    started = %Event{
      kind: :media_started,
      provider: :telnyx,
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: binding.provider_call_session_id,
      stream_id: "stream-initial"
    }

    assert :ok =
             TestTelephonySocket.run(socket, fn -> OutgoingLeg.dispatch(leg, started, 2_000) end)

    assert :ok = CallEngine.TestCallStartup.await_open(plan)
    assert {:ok, snapshot} = MediaSupervisor.snapshot(context.leg_id)
    assert binding.incarnation_id == room.incarnation_id
    assert snapshot.attachment.admission == :main
    assert snapshot.attachment.transfer_attempt_id == nil
    dtmf = lifecycle_event(:dtmf, digit: "1")
    assert :ok = TestTelephonySocket.run(socket, fn -> OutgoingLeg.dispatch(leg, dtmf, 1_000) end)
  end

  test "submits the same outbound-leg contract through a configured Twilio service", context do
    service = twilio_service(self(), answering_machine_detection: :detect)
    request = %{request() | service_id: "twilio-primary"}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_twilio_dial, dial}

    assert dial.leg_id == context.leg_id
    assert dial.from == "+15550001000"
    assert dial.to == "+15550001001"
    assert dial.answering_machine_detection == :detect

    assert dial.callback_url ==
             "https://voice.example.test/voice/api/telephony/twilio/outbound_ingress/events/#{context.leg_id}"

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url, service)
    assert binding.provider == :twilio
    assert binding.leg == leg
    assert binding.provider_call_control_id == "CA00000000000000000000000000000001"
    assert binding.provider_call_leg_id == "CA00000000000000000000000000000001"
    assert binding.provider_call_session_id == nil
  end

  test "a scoped outgoing owner remains discoverable by provider leg without client state",
       context do
    original = service(self(), [])

    reference = %{
      original.identity.service_reference
      | credential_owner: :platform,
        credential_name: "telnyx"
    }

    service = %{original | identity: %{original.identity | service_reference: reference}}
    request = %{request() | service_reference: reference}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)

    assert_receive {:test_telephony_dial, dial}
    assert dial.callback_url == "https://voice.example.test/voice/webhooks/platform/telnyx"

    body =
      JSON.encode!(%{
        data: %{
          payload: %{connection_id: "voice-application-1", call_leg_id: "outbound-call-leg"}
        }
      })

    assert {:ok, ^service, {:outgoing, ^leg}} =
             Vxpipe.Gateway.Telephony.WebhookService.scoped_telnyx_owner(:platform, body)
  end

  test "rejects an inbound-only service before submitting a dial", context do
    service = service(self(), outbound_number: nil)

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission
             )

    assert {:error, :invalid_outbound_telephony_request} = OutgoingLeg.await(leg, 1_000)
    refute_receive {:test_telephony_dial, _request}
  end

  test "adopts a signed outgoing event after an unknown submission", context do
    service = service(self(), api_key: "unknown:#{:erlang.pid_to_list(self())}")
    request = request()

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_telephony_dial, dial}

    mismatched = %{outgoing_event(context.leg_id) | to: "+15550001002"}

    assert {:error, :telephony_leg_mismatch} =
             CallIngress.handle_event([], service, mismatched, {:outgoing, leg})

    event = outgoing_event(context.leg_id)
    assert :ok = CallIngress.handle_event([], service, event, {:outgoing, leg})

    assert {:ok, ^leg} =
             LegSupervisor.lookup(service.identity, "outbound-call-leg")

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url, service)
    assert binding.leg == leg
    assert binding.provider_call_control_id == event.provider_call_control_id
    assert binding.provider_call_leg_id == event.provider_call_leg_id
    assert binding.provider_call_session_id == event.provider_call_session_id
  end

  test "adopts an out-of-order Twilio answered callback after an unknown submission", context do
    service =
      twilio_service(self(),
        auth_token: "unknown:#{:erlang.pid_to_list(self())}"
      )

    request = %{request() | service_id: "twilio-primary"}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_twilio_dial, dial}

    event = twilio_answered_event(context.leg_id)
    assert :ok = CallIngress.handle_event([], service, event, {:outgoing, leg})
    refute_receive {:test_twilio_dial, _duplicate}

    assert {:ok, ^leg} =
             LegSupervisor.lookup(service.identity, event.provider_call_leg_id)

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url, service)
    assert binding.leg == leg
    assert binding.provider_call_control_id == event.provider_call_control_id
    assert binding.provider_call_leg_id == event.provider_call_leg_id
    assert binding.provider_call_session_id == nil
  end

  test "the engine connector resolves the tenant service and starts one supervised leg",
       context do
    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self())]
      )

    connector = [
      leg_id: fn -> context.leg_id end,
      leg_supervisor: LegSupervisor,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    assert {:ok,
            %OutgoingLegReference{
              leg: leg,
              leg_id: leg_id,
              supervisor: LegSupervisor
            }} = OutgoingLegConnector.connect(connector, request(), 1_000)

    assert is_pid(leg)
    assert leg_id == context.leg_id
    assert_receive {:test_telephony_dial, %{leg_id: ^leg_id}}
    refute_receive {:test_telephony_dial, _duplicate}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(leg_id)
  end

  test "configured machine detection ends the exact attempted leg once", context do
    service = service(self(), answering_machine_detection: :detect)
    leg = start_accepted_leg(context, service)
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:machine), 1_000)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{
                        leg_id: leg_id,
                        provider_call_control_id: "outbound-call-control"
                      },
                      reason: :answering_machine
                    }}

    assert leg_id == context.leg_id
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _duplicate}
  end

  test "human and unknown detection keep waiting for explicit acceptance", context do
    service = service(self(), answering_machine_detection: :detect)
    leg = start_accepted_leg(context, service)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:human), 1_000)
    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:unknown), 1_000)
    refute_receive {:test_telephony_end_leg, _request}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
  end

  test "disabled detection and mismatched lifecycle evidence cannot end the leg", context do
    leg = start_accepted_leg(context, service(self(), []))

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:machine), 1_000)

    mismatched = %{
      ended_event(:failed)
      | provider_call_control_id: "another-call-control"
    }

    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, mismatched, 1_000)
    refute_receive {:test_telephony_end_leg, _request}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
  end

  test "a carrier-ended event retires locally without a redundant hangup", context do
    leg = start_accepted_leg(context, service(self(), []))
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:busy), 1_000)

    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _request}
  end

  test "reports one carrier leg and its provider-timed connection duration", context do
    service = service(self(), [])
    started_at = ~U[2026-09-12 04:00:00.000Z]

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()},
               usage_clock: fn -> started_at end
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_usage_observations, [started]}
    assert_receive {:test_telephony_dial, _dial}
    assert_receive {:test_usage_observations, [identified]}

    assert started.measurement.component == "carrier_legs"
    assert started.measurement.quantity == 1
    assert started.attribution.leg_id == context.leg_id
    assert started.provider.operation_id == nil

    assert identified.provider.name == "telnyx"
    assert identified.provider.integration_id == "telnyx-primary"
    assert identified.provider.operation_id == "outbound-call-leg"
    assert identified.provider.session_id == "outbound-call-session"

    answered =
      lifecycle_event(:answered,
        provider_event_id: "event-answered-usage",
        occurred_at: ~U[2026-09-12 04:00:03.250Z]
      )

    assert :ok = OutgoingLeg.dispatch(leg, answered, 1_000)
    assert_receive {:test_usage_observations, [connected]}
    assert connected.measurement == nil
    assert connected.delivery_id == "event-answered-usage"

    assert :ok = OutgoingLeg.dispatch(leg, answered, 1_000)
    refute_receive {:test_usage_observations, _duplicate_connected}

    mismatched = %{
      ended_event(:hangup)
      | provider_event_id: "event-ended-mismatched-usage",
        provider_call_control_id: "another-call-control",
        occurred_at: ~U[2026-09-12 04:01:00.000Z]
    }

    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, mismatched, 1_000)
    refute_receive {:test_usage_observations, _mismatched_usage}

    monitor = Process.monitor(leg)

    ended =
      lifecycle_event(:ended,
        provider_event_id: "event-ended-usage",
        occurred_at: ~U[2026-09-12 04:01:08.750Z],
        end_reason: :hangup
      )

    assert :ok = OutgoingLeg.dispatch(leg, ended, 1_000)
    assert_receive {:test_usage_observations, [duration]}
    assert duration.outcome == :succeeded
    assert duration.measurement.component == "connection_duration"
    assert duration.measurement.quantity == 65_500
    assert duration.measurement.provenance == :provider_reported
    assert duration.provider.operation_id == "outbound-call-leg"
    assert duration.delivery_id == "event-ended-usage"
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
  end

  for failure <- [:media_unavailable, :expired_deadline] do
    test "retains one validated attempt when preparation fails with #{failure}", context do
      runtime = [usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}]

      runtime =
        if unquote(failure) == :expired_deadline,
          do: Keyword.merge(runtime, deadline_ms: 10, monotonic_clock: fn -> 10 end),
          else: runtime

      assert {:ok, leg} =
               LegSupervisor.start_outgoing(
                 LegSupervisor,
                 context.leg_id,
                 request(),
                 service(self(), []),
                 :unavailable_outgoing_test_media_admission,
                 runtime
               )

      expected =
        if unquote(failure) == :expired_deadline,
          do: :outbound_connection_unavailable,
          else: :media_admission_unavailable

      assert {:error, ^expected} = OutgoingLeg.await(leg, 1_000)
      assert :ok = OutgoingLeg.disconnect(leg, 1_000)
      OutgoingLeg.abandon(leg)
      assert {:error, ^expected} = OutgoingLeg.await(leg, 1_000)
      assert_receive {:test_usage_observations, [started]}
      assert_receive {:test_usage_observations, [failed]}
      assert started.measurement.component == "carrier_legs"
      assert failed.attempt_id == started.attempt_id
      assert failed.outcome == :failed
      assert failed.measurement == nil
      assert failed.provider.operation_id == nil
      refute_received {:test_usage_observations, _}
      refute_received {:test_telephony_dial, _}
    end
  end

  for invalid <- [:request, :service] do
    test "invalid #{invalid} is rejected before usage or media access", context do
      request = if unquote(invalid) == :request, do: %{request() | to: "invalid"}, else: request()
      service = service(self(), [])

      service =
        if unquote(invalid) == :service, do: %{service | outbound_number: nil}, else: service

      assert {:ok, leg} =
               LegSupervisor.start_outgoing(
                 LegSupervisor,
                 context.leg_id,
                 request,
                 service,
                 :unavailable_outgoing_test_media_admission,
                 usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
               )

      assert {:error, :invalid_outbound_telephony_request} = OutgoingLeg.await(leg, 1_000)
      refute_received {:test_usage_observations, _}
      refute_received {:test_telephony_dial, _}
    end
  end

  test "retains a rejected carrier dial without inventing duration or provider identity",
       context do
    service = service(self(), api_key: "reject:#{:erlang.pid_to_list(self())}")

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
             )

    assert {:error, :command_rejected} = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_usage_observations, [started]}
    assert_receive {:test_telephony_dial, _dial}
    assert_receive {:test_usage_observations, [failed]}

    assert started.measurement.component == "carrier_legs"
    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert failed.provider.operation_id == nil
    assert failed.provider.session_id == nil
  end

  test "connector cleanup ends a known exact carrier leg before retiring it", context do
    availability = :atomics.new(1, [])
    :atomics.put(availability, 1, 1)

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options(self())],
        service_availability: fn -> :atomics.get(availability, 1) == 1 end
      )

    connector = [
      leg_id: fn -> context.leg_id end,
      leg_supervisor: LegSupervisor,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    assert {:ok, %OutgoingLegReference{leg: leg} = reference} =
             OutgoingLegConnector.connect(connector, request(), 1_000)

    assert_receive {:test_telephony_dial, _dial}
    monitor = Process.monitor(leg)
    :atomics.put(availability, 1, 0)

    assert :ok = OutgoingLegConnector.disconnect(connector, reference)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{
                        leg_id: leg_id,
                        provider_call_control_id: "outbound-call-control"
                      },
                      reason: :transfer_cancelled
                    }}

    assert leg_id == context.leg_id
    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:hangup), 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _duplicate}
  end

  test "failed fresh credentials create no leg, media reservation or dial", context do
    repository = Vxpipe.Gateway.TestTelephonyServiceRepository
    snapshot = repository.snapshot(service_options(self()))

    revoked = %{
      snapshot
      | credential: %{
          snapshot.credential
          | credential: %{snapshot.credential.credential | status: :revoked}
        }
    }

    media_before = :sys.get_state(context.media_admission)

    for result <- [
          {:error, :service_not_found},
          {:error, :repository_unavailable},
          {:ok, revoked}
        ] do
      registry =
        ServiceRegistry.init!(
          enabled: true,
          public_base_url: "https://voice.example.test/voice",
          telephony_service_repository: {repository, fn :resolve, _arguments -> result end}
        )

      connector = [
        service_registry: registry,
        media_admission: context.media_admission,
        leg_id: fn ->
          send(self(), :unexpected_leg_allocation)
          context.leg_id
        end
      ]

      assert {:error, :outbound_connection_unavailable} =
               OutgoingLegConnector.connect(connector, request(), 1_000)

      assert {:error, :leg_not_found} = LegSupervisor.lookup_outgoing(context.leg_id)
      assert :sys.get_state(context.media_admission) == media_before
      refute_receive :unexpected_leg_allocation
      refute_receive {:test_telephony_dial, _request}
    end
  end

  test "a verified retired owner cannot deliver to a replacement leg", context do
    service = service(self(), [])
    leg = start_accepted_leg(context, service)

    body =
      JSON.encode!(%{
        "data" => %{
          "payload" => %{
            "connection_id" => service.identity.provider_connection_id,
            "call_leg_id" => "outbound-call-leg",
            "client_state" => Vxpipe.Providers.Telnyx.ClientState.encode(context.leg_id)
          }
        }
      })

    assert {:ok, ^service, {:outgoing, ^leg} = owner} =
             Vxpipe.Gateway.Telephony.WebhookService.scoped_telnyx_owner(
               service.identity.service_reference.credential_owner,
               body
             )

    monitor = Process.monitor(leg)
    :ok = LegSupervisor.stop_outgoing(context.leg_id)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :shutdown}

    replacement = start_accepted_leg(context, service)

    assert {:error, :telephony_leg_mismatch} =
             CallIngress.handle_event([], service, ended_event(:hangup), owner)

    assert {:ok, ^replacement} = LegSupervisor.lookup_outgoing(context.leg_id)
    assert :ok = OutgoingLeg.await(replacement, 1_000)
    refute_receive {:test_telephony_end_leg, _request}
  end

  test "credential lookup cannot start a dial after the connector deadline", context do
    repository = Vxpipe.Gateway.TestTelephonyServiceRepository
    snapshot = repository.snapshot(service_options(self()))
    clock = :atomics.new(1, [])

    registry =
      ServiceRegistry.init!(
        enabled: true,
        public_base_url: "https://voice.example.test/voice",
        adapters: %{telnyx: Vxpipe.Gateway.TestTelephonyAdapter},
        telephony_service_repository:
          {repository,
           fn :resolve, _arguments ->
             :atomics.put(clock, 1, 100)
             {:ok, snapshot}
           end}
      )

    connector = [
      leg_id: fn -> context.leg_id end,
      leg_supervisor: LegSupervisor,
      media_admission: context.media_admission,
      service_registry: registry,
      monotonic_clock: fn -> :atomics.get(clock, 1) end
    ]

    assert {:error, :outbound_connection_unavailable} =
             OutgoingLegConnector.connect(connector, request(), 50)

    assert {:error, :leg_not_found} = LegSupervisor.lookup_outgoing(context.leg_id)
    refute_receive {:test_telephony_dial, _request}
  end

  defp start_probe_command(:dial, service, leg_id) do
    DialSupervisor.submit(self(), service, %Dial{
      leg_id: leg_id,
      from: "+15550001000",
      to: "+15550001001",
      callback_url: "https://example.test/callback",
      media_url: "wss://example.test/media",
      answering_machine_detection: :disabled
    })
  end

  defp start_probe_command(:end, service, leg_id),
    do: DialSupervisor.end_leg(self(), service, leg_id, "outbound-call-control", :call_cancelled)

  defp request do
    %OutboundLegRequest{
      tenant_id: "tenantkey1234567",
      actor_id: "actor-outbound",
      call_id: "call-outbound",
      room_id: "room-outbound",
      incarnation_id: "rinc-outbound",
      participant_id: "participant-support",
      service_id: "telnyx-primary",
      service_reference:
        Vxpipe.Gateway.TestTelephonyServiceRepository.reference(service_options(self())),
      to: "+15550001001"
    }
  end

  defp service(observer, overrides) do
    assert {:ok, service} =
             ConfiguredService.new(service_options(observer, overrides))

    %{
      service
      | identity: %{
          service.identity
          | service_reference:
              Vxpipe.Gateway.TestTelephonyServiceRepository.reference(
                service_options(observer, overrides)
              )
        }
    }
  end

  defp service_options(observer, overrides \\ []) do
    Keyword.merge(
      [
        id: "telnyx-primary",
        ingress_key: "outbound_ingress",
        scope: {:tenant, "tenantkey1234567"},
        provider: :telnyx,
        provider_connection_id: "voice-application-1",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "observer:#{:erlang.pid_to_list(observer)}",
        outbound_number: "+15550001000",
        public_base_url: "https://voice.example.test/voice",
        adapter: Vxpipe.Gateway.TestTelephonyAdapter
      ],
      overrides
    )
  end

  defp twilio_service(observer, overrides) do
    options =
      Keyword.merge(
        [
          id: "twilio-primary",
          ingress_key: "outbound_ingress",
          scope: {:tenant, "tenantkey1234567"},
          provider: :twilio,
          account_sid: "AC00000000000000000000000000000000",
          auth_token: "observer:#{:erlang.pid_to_list(observer)}",
          outbound_number: "+15550001000",
          public_base_url: "https://voice.example.test/voice",
          adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
        ],
        overrides
      )

    assert {:ok, service} = ConfiguredService.new(options)

    %{
      service
      | identity: %{
          service.identity
          | service_reference: Vxpipe.Gateway.TestTelephonyServiceRepository.reference(options)
        }
    }
  end

  defp start_accepted_leg(context, service) do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_telephony_dial, %{leg_id: leg_id}}
    assert leg_id == context.leg_id
    leg
  end

  defp answering_machine_event(result) do
    lifecycle_event(:answering_machine,
      answering_machine: result,
      provider_event_id: "event-amd-#{result}"
    )
  end

  defp ended_event(reason) do
    lifecycle_event(:ended, end_reason: reason, provider_event_id: "event-ended-#{reason}")
  end

  defp lifecycle_event(kind, overrides) do
    struct!(
      Event,
      Keyword.merge(
        [
          kind: kind,
          provider: :telnyx,
          provider_event_id: "event-lifecycle",
          provider_connection_id: "voice-application-1",
          provider_call_control_id: "outbound-call-control",
          provider_call_leg_id: "outbound-call-leg",
          provider_call_session_id: "outbound-call-session",
          occurred_at: ~U[2026-09-11 14:30:00Z],
          occurred_at_provenance: :provider_reported
        ],
        overrides
      )
    )
  end

  defp outgoing_event(leg_id) do
    %Event{
      kind: :outgoing,
      provider: :telnyx,
      provider_event_id: "event-outgoing",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "outbound-call-control",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      occurred_at: ~U[2026-09-11 13:45:00Z],
      occurred_at_provenance: :provider_reported,
      from: "+15550001000",
      to: "+15550001001"
    }
  end

  defp twilio_answered_event(leg_id) do
    %Event{
      kind: :answered,
      provider: :twilio,
      provider_event_id: "CA00000000000000000000000000000002:status:2",
      provider_connection_id: "AC00000000000000000000000000000000",
      provider_call_control_id: "CA00000000000000000000000000000002",
      provider_call_leg_id: "CA00000000000000000000000000000002",
      provider_call_session_id: nil,
      leg_id: leg_id,
      occurred_at: ~U[2026-09-11 13:46:00Z],
      occurred_at_provenance: :locally_measured,
      sequence_number: 2,
      from: "+15550001000",
      to: "+15550001001"
    }
  end

  defp consume_media(media_admission, media_url, service) do
    %URI{path: path} = URI.parse(media_url)
    [token | _rest] = path |> String.split("/", trim: true) |> Enum.reverse()

    if service.identity.provider == :twilio,
      do: MediaAdmission.consume(media_admission, "outbound_ingress", token, service),
      else: MediaAdmission.consume(media_admission, "outbound_ingress", token)
  end
end
