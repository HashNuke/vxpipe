defmodule Vxpipe.Gateway.Telephony.TelnyxCallHarnessTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  alias Vxpipe.CallEngine.{
    TestSelectiveAgentRuntimeModelProvider,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport
  }

  alias Vxpipe.Gateway.TestTelephonySocket

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    LegSupervisor,
    MediaAdmission,
    MediaSupervisor
  }

  alias Vxpipe.Providers.Telnyx.{ClientState, TelephonyMediaSocket}

  alias Vxpipe.Gateway.{
    TelnyxCallScenario,
    TelnyxFixture,
    TelephonyHarnessBackend
  }

  @incoming_leg_id "leg-inbound-harness"
  @outgoing_leg_id "leg-outbound-harness"
  @received_at DateTime.to_unix(~U[2026-09-11 15:00:05Z])

  setup context do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    text_to_speech = [
      providers: %{
        Vxpipe.Providers.Deepgram.TTSSession => [
          enabled: true,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: self()],
          maximum_requests: 2
        ]
      }
    ]

    speech_to_text = [
      providers: %{
        Vxpipe.Providers.ElevenLabs.STTSession => [
          enabled: true,
          wire_module: Vxpipe.CallEngine.TestElevenLabsScribeTransport,
          wire_options: [observer: self()]
        ],
        Vxpipe.Providers.Deepgram.STTSession => [
          enabled: true,
          wire_module: TestSpeechToTextTransport,
          wire_options: [observer: self()],
          media_ingress: [
            maximum_frames: 8,
            maximum_bytes: 1_024,
            maximum_age_ms: 1_000,
            maximum_consecutive_overflows: 2
          ]
        ]
      }
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    admission = start_supervised!({MediaAdmission, name: nil})

    scenario_options =
      if outcome = context[:initial_outcome] do
        configured = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

        Application.put_env(
          :vxpipe_call_engine,
          Vxpipe.CallEngine.Application,
          Keyword.put(configured, :call_lifecycle,
            readiness_timeout_ms: 30_000,
            idle_timeout_ms: 15_000,
            timer: {Vxpipe.CallEngine.TestCallLifecycleTimer, observer: self()}
          )
        )

        [
          caller_vad: context[:caller_vad] == true,
          caller_stt: if(context[:caller_recovery], do: :scribe, else: :default),
          language: context[:language],
          command_mode: context[:command_mode] || "observer",
          transfer_policy:
            if(context[:recovery_transfer],
              do: %{recovery_destination: "human-support"},
              else: %{}
            ),
          model: if(outcome == :model, do: "test:blocked-unavailable", else: "test:blocked"),
          wait_sounds: if(outcome in [:max_duration, :disconnected], do: nil, else: %{})
        ]
      else
        if mode = context[:transfer_wait_mode],
          do: Vxpipe.Gateway.PhoneHandoffAssertions.scenario_options(mode),
          else: []
      end

    scenario =
      TelnyxCallScenario.build(
        self(),
        public_key,
        admission,
        @incoming_leg_id,
        @outgoing_leg_id,
        scenario_options
      )

    backend =
      start_supervised!(
        {TelephonyHarnessBackend,
         claim: scenario.claim, runtime_options: scenario.runtime_options}
      )

    endpoint =
      Vxpipe.Gateway.TestTelephonyServiceRepository.endpoint(
        telephony: [
          enabled: true,
          clock: fn -> @received_at end,
          handler: {CallIngress, backend: TelephonyHarnessBackend.backend(backend)},
          media_admission: admission,
          services: [scenario.service_options],
          service_availability: fn -> TelephonyHarnessBackend.available?(backend) end
        ]
      )

    on_exit(fn ->
      stop_room(scenario.plan.tenant_id, scenario.plan.room_id)

      LegSupervisor.stop(
        Vxpipe.Gateway.TestTelephonyServiceRepository.configured(scenario.service_options).identity,
        "inbound-call-leg"
      )

      LegSupervisor.stop_outgoing(@outgoing_leg_id)
      LegSupervisor.stop_outgoing("peer-" <> @incoming_leg_id)
    end)

    %{
      backend: backend,
      endpoint: endpoint,
      plan: scenario.plan,
      service_identity:
        Vxpipe.Gateway.TestTelephonyServiceRepository.configured(scenario.service_options).identity,
      private_key: private_key
    }
  end

  @tag initial_outcome: :ready
  test "room death during a blocked incoming answer retains the carrier owner until ended",
       context do
    TelephonyHarnessBackend.block_answer(context.backend, self())
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         send(
           observer,
           {:incoming_response, post_fixture(context, "call-initiated-incoming").status}
         )
       end}
    )

    assert_receive {:incoming_answer_pending, worker}, 2_000
    on_exit(fn -> send(worker, :reject_incoming_answer) end)
    worker_monitor = Process.monitor(worker)
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
    leg_monitor = Process.monitor(leg)
    claim = TelephonyHarnessBackend.claim(context.backend)
    refute_received {:test_telephony_answer, _}
    refute_received {:test_agent_runtime_model_preparing, _}

    assert :ok =
             Vxpipe.CallEngine.end_call(
               claim.call.tenant_key,
               claim.call.room_id,
               claim.call.incarnation_id
             )

    assert_receive {:test_telephony_end_leg, request}, 2_000
    assert request.leg.provider_call_control_id == "inbound-call-control"
    assert_receive {:incoming_response, 200}
    refute_received {:DOWN, ^leg_monitor, :process, ^leg, _}

    assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
             200

    # Carrier termination does not drain a still-pending local command.
    assert {:ok, ^leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
    send(worker, :reject_incoming_answer)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 2_000
    assert_receive {:DOWN, ^leg_monitor, :process, ^leg, :normal}
    refute_received {:test_telephony_answer, _}
  end

  for stage <- [:before_media, :after_media] do
    @tag initial_outcome: :ready
    @tag carrier_hangup: stage
    test "signed incoming hangup ends its exact room #{stage}", context do
      assert post_fixture(context, "call-initiated-incoming").status == 200
      assert_receive {:test_telephony_answer, answer}, 2_000
      claim = TelephonyHarnessBackend.claim(context.backend)

      assert {:ok, monitor} =
               Vxpipe.CallEngine.monitor_room(
                 context.plan.tenant_id,
                 context.plan.room_id,
                 claim.call.incarnation_id
               )

      if context.carrier_hangup == :after_media do
        assert post_fixture(context, "call-answered-incoming").status == 200

        transport =
          start_supervised!(
            Supervisor.child_spec({TestTelephonySocket, observer: self()}, restart: :temporary)
          )

        assert {:ok, _binding, _socket} =
                 TestTelephonySocket.open(transport, TelephonyMediaSocket, fn ->
                   TelnyxFixture.open_media(context.endpoint, answer.media_url, %{
                     "call_control_id" => "inbound-call-control",
                     "call_session_id" => "inbound-call-session",
                     "client_state" => ClientState.encode(@incoming_leg_id),
                     "from" => "+15550001001",
                     "stream_id" => "inbound-stream",
                     "to" => "+15550001000"
                   })
                 end)
      end

      assert post_fixture(context, "call-hangup-incoming", %{
               "call_leg_id" => "unrelated-leg"
             }).status != 200

      refute_received {:DOWN, ^monitor, :process, _, _}

      assert post_fixture(context, "call-hangup-incoming", %{
               "call_leg_id" => "inbound-call-leg"
             }).status == 200

      assert_receive {:DOWN, ^monitor, :process, _, {:shutdown, :remote_hangup}}, 2_000
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, language: "fr"
  test "a caller configured for French does not receive the English callback recording",
       context do
    {speech, _} = start_recovery_call(context)

    [{media, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, @incoming_leg_id})

    monitor = Process.monitor(media)
    GenServer.stop(speech, :normal)
    assert_receive {:DOWN, ^monitor, :process, ^media, _reason}, 2_000
    refute_receive {:test_recovery_playback, _, _}
  end

  @tag initial_outcome: :ready, caller_recovery: true
  @tag recovery_permission: true
  test "a delayed playout request without its cleared output grant is inert", context do
    {_speech, _socket} = start_recovery_call(context)

    [{room, _}] =
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {context.plan.tenant_id, context.plan.room_id}
      )

    [{media, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, @incoming_leg_id})

    send(media, {:play_caller_recovery, room, "retired-grant", :hearing, 0})
    assert :sys.get_state(media).recovery_cue == nil
  end

  @tag initial_outcome: :ready, caller_recovery: true, caller_vad: true, commercial: true
  test "a completed short acknowledgment leaves its recognizer listening after the offset deadline",
       context do
    {speech, _socket} = start_recovery_call(context)

    [{room, _}] =
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {context.plan.tenant_id, context.plan.room_id}
      )

    wire = Vxpipe.CallEngine.TestElevenLabsScribeTransport
    wire.deliver(speech, {:partial, "Okay"})
    {capability, turn} = await_open_question(room, System.monotonic_time(:millisecond) + 2_000)
    state = :sys.get_state(capability)

    send(
      capability,
      {:vxpipe_acoustic_activity, state.session, turn, :speech_ended,
       %{
         source_epoch: state.acoustic_epoch,
         sequence: 1,
         at_ms: System.monotonic_time(:millisecond)
       }}
    )

    %{stall_watch: %{token: token}} = :sys.get_state(capability)

    wire.deliver(speech, {:segment, "Okay."})
    wire.deliver(speech, {:partial, ""})
    assert_receive {:test_agent_runtime_stream, _, _}, 3_000
    send(capability, {:stt_stall_timeout, token})
    settled = :sys.get_state(capability)
    assert settled.session == state.session
    assert settled.stall_watch == nil
    assert settled.reported_stall == nil
    assert :sys.get_state(room).connections[@incoming_leg_id].speech_recovery == :eligible
    refute_received {:scribe_started, _}
    refute_received {:test_recovery_playback, _, _}
  end

  @tag initial_outcome: :ready, caller_recovery: true, caller_vad: true, commercial: true
  test "a stalled open question replaces recognition on the same caller media socket", context do
    {room, replacement, socket} = start_stalled_recovery(context)
    capability = :sys.get_state(room).connections[@incoming_leg_id].speech_to_text.capability
    state = :sys.get_state(capability)

    frame =
      struct(
        Vxpipe.CallEngine.Media.AudioFrame,
        Map.merge(
          state.identity,
          Map.merge(state.media_format, %{
            track_id: "phone",
            sequence_number: 1279,
            timestamp: 0,
            received_at: System.monotonic_time(:millisecond),
            payload: <<0::320>>
          })
        )
      )

    # Phone packets can arrive before a replacement channel can service calls.
    channel = Vxpipe.CallEngine.Speech.Channel.address(state.session)
    :ok = :sys.suspend(channel)

    try do
      parent = self()

      start_supervised!(
        {Task,
         fn ->
           send(
             parent,
             {:early_audio,
              Vxpipe.CallEngine.Capability.SpeechToText.push_audio(capability, frame)}
           )
         end}
      )

      assert_receive {:early_audio, {:error, :policy_denied}}, 500
    after
      :sys.resume(channel)
    end

    refute_received {:scribe_audio, ^replacement, _}
    Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(replacement, {:ready, "fresh-scribe"})
    await_recovery_phase(room, :awaiting_repeat, System.monotonic_time(:millisecond) + 9_000)
    assert_receive {:test_phone_output, ^socket, packet}, 2_000
    assert JSON.decode!(packet)["event"] in ["clear", "media"]

    Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(
      replacement,
      {:segment, "Do you service commercial properties?"}
    )

    Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(replacement, {:partial, ""})
    assert_receive {:test_agent_runtime_stream, _provider, _request}, 3_000
    refute_received {:test_agent_runtime_stream, _, _}
    refute_received {:test_recovery_playback, _, _}
  end

  @tag initial_outcome: :ready, caller_recovery: true
  test "a confirmed recognizer disconnect gets one fresh allocation while phone audio remains healthy",
       context do
    {speech, _socket} = start_recovery_call(context)
    GenServer.stop(speech, :normal)
    assert_receive {:scribe_started, replacement}, 2_000
    refute_received {:test_recovery_playback, _, _}
    GenServer.stop(replacement, :normal)
    assert_receive {:test_recovery_playback, "inbound-call-control", _id}, 2_000
    refute_received {:scribe_started, _}
  end

  for failure <- [:readiness_timeout, :no_repeat, :replacement_failure] do
    @tag initial_outcome: :ready, caller_recovery: true, caller_vad: true, commercial: true
    @tag recovery_scenario: true
    test "recovery enters carrier fallback once on #{failure}", context do
      {room, replacement, _socket} = start_stalled_recovery(context)

      case unquote(failure) do
        :readiness_timeout ->
          expire_recovery(room, :hearing)

        :no_repeat ->
          Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(
            replacement,
            {:ready, "replacement"}
          )

          expire_recovery(room, :awaiting_repeat)

        :replacement_failure ->
          Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(
            replacement,
            {:ready, "replacement"}
          )

          GenServer.stop(replacement, :normal)
      end

      assert_receive {:test_recovery_playback, "inbound-call-control", id}, 2_000
      refute_received {:scribe_started, _}

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(id)
             }).status == 200

      assert_receive {:test_telephony_end_leg, _}, 2_000

      assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
               200
    end
  end

  defp expire_recovery(room, phase) do
    await_recovery_phase(room, phase, System.monotonic_time(:millisecond) + 9_000)
    %{timer: {_, token}} = :sys.get_state(room).connections[@incoming_leg_id].speech_recovery
    send(room, {:caller_recovery_expired, @incoming_leg_id, token})
  end

  defp start_stalled_recovery(context) do
    {speech, socket} = start_recovery_call(context)

    [{room, _}] =
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {context.plan.tenant_id, context.plan.room_id}
      )

    Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(
      speech,
      {:partial, "Do you service commercial properties?"}
    )

    {capability, turn} = await_open_question(room, System.monotonic_time(:millisecond) + 2_000)
    session = :sys.get_state(capability).session

    send(
      capability,
      {:vxpipe_acoustic_activity, session, turn, :speech_ended,
       %{
         source_epoch: :sys.get_state(capability).acoustic_epoch,
         sequence: System.unique_integer([:positive, :monotonic]),
         at_ms: System.monotonic_time(:millisecond) - 4_000
       }}
    )

    assert_receive {:scribe_started, replacement}, 2_000
    refute replacement == speech
    {room, replacement, socket}
  end

  defp await_recovery_phase(room, phase, deadline) do
    connection = Map.fetch!(:sys.get_state(room).connections, @incoming_leg_id)

    case connection.speech_recovery do
      %{phase: ^phase} ->
        :ok

      other ->
        assert System.monotonic_time(:millisecond) < deadline,
               "recovery phase: #{inspect(if is_map(other), do: Map.take(other, [:phase, :ready?, :hearing_done?]), else: other)}"

        receive do
        after
          10 -> await_recovery_phase(room, phase, deadline)
        end
    end
  end

  defp await_open_question(room, deadline) do
    connection = Map.fetch!(:sys.get_state(room).connections, @incoming_leg_id)

    case connection.speech_to_text do
      %{turn: %{turn_ref: turn}, capability: capability} when is_reference(turn) ->
        {capability, turn}

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "caller turn never opened"

        receive do
        after
          10 -> await_open_question(room, deadline)
        end
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, commercial: true
  test "commercial-property barge-in interrupts phone output before the recognizer disconnects",
       context do
    {speech, socket, voice} = start_recovery_media(context)
    scribe = Vxpipe.CallEngine.TestElevenLabsScribeTransport
    scribe.deliver(speech, {:segment, "Do you offer gardening services?"})
    scribe.deliver(speech, {:partial, ""})
    assert_receive {:test_agent_runtime_stream, provider, _}, 3_000
    {:ok, response} = ModelResponse.new(text: "We offer gardening services.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_control, ^voice, speak}, 2_000
    assert %{"type" => "Speak", "text" => "We offer gardening services."} = JSON.decode!(speak)
    assert_receive {:test_tts_control, ^voice, flush}, 2_000
    assert JSON.decode!(flush)["type"] == "Flush"

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"gardening"})
    )

    TestTextToSpeechTransport.deliver_audio(
      voice,
      :binary.copy(<<1000::little-signed-16>>, 9_600)
    )

    assert_receive {:test_phone_output, ^socket, packet}, 2_000
    assert %{"event" => "media"} = JSON.decode!(packet)
    scribe.deliver(speech, {:partial, "Do you service commercial properties?"})
    assert_receive {:test_phone_output, ^socket, ~s({"event":"clear"})}, 2_000
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, "inbound-call-control", id}, 2_000

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_telephony_end_leg, _}, 2_000
  end

  @tag initial_outcome: :ready, caller_recovery: true, recovery_transfer: true
  test "a configured fallback journals and announces the handoff before submitting one linked dial",
       context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_transfer_announcement, "inbound-call-control", id}, 2_000
    refute_received {:test_linked_dial, _}

    for _duplicate <- 1..2 do
      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(id)
             }).status == 200
    end

    assert_receive {:test_linked_dial, request}, 2_000
    assert request.to == "+15550001002"
    assert request.caller == "inbound-call-control"

    assert {:caller_recovery, :transfer_requested, request.id} in TelephonyHarnessBackend.operations(
             context.backend
           )

    refute_received {:test_linked_dial, _}
    refute_received {:test_telephony_end_leg, _}
  end

  for outcome <- [:bridged, :no_answer, :busy, :rejected, :abandoned, :platform_after_bridge] do
    @tag initial_outcome: :ready, caller_recovery: true, recovery_transfer: true
    test "human fallback handles #{outcome} across AI room shutdown", context do
      {speech, _} = start_recovery_call(context)
      exhaust_recognition(speech)
      assert_receive {:test_transfer_announcement, _, id}, 2_000

      if unquote(outcome) in [:bridged, :abandoned],
        do: stop_transfer_room!(context.plan)

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(id)
             }).status == 200

      assert_receive {:test_linked_dial, request}, 2_000
      assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")

      case unquote(outcome) do
        :bridged ->
          assert peer_event(context, request.id, "call.bridged").status == 200
          assert :sys.get_state(leg).recovery.phase == :bridged
          refute_received {:test_telephony_end_leg, _}
          assert peer_event(context, request.id, "call.hangup").status == 200

          assert_receive {:test_telephony_end_leg,
                          %{leg: %{provider_call_control_id: "inbound-call-control"}}},
                         2_000

        :platform_after_bridge ->
          assert peer_event(context, request.id, "call.bridged").status == 200
          assert :sys.get_state(leg).recovery.phase == :bridged
          stop_transfer_room!(context.plan)
          assert :sys.get_state(leg).recovery.phase == :bridged
          refute_received {:test_telephony_end_leg, _}
          call = TelephonyHarnessBackend.claim(context.backend).call

          row = %{
            tenant_key: call.tenant_key,
            call_id: call.id,
            room_id: call.room_id,
            incarnation_id: call.incarnation_id,
            incarnation_binding_verified: true,
            hangup_requested_at: DateTime.utc_now(),
            gateway_cleanup_required: false
          }

          assert :requested = Vxpipe.Gateway.CallCleanupRecovery.reconcile(row, [])

          assert_receive {:test_telephony_end_leg,
                          %{leg: %{provider_call_control_id: "inbound-call-control"}}},
                         2_000

          assert_receive {:test_telephony_end_leg,
                          %{leg: %{provider_call_control_id: "peer-control"}}},
                         2_000

          refute {:caller_recovery, :transfer_abandoned, request.id} in TelephonyHarnessBackend.operations(
                   context.backend
                 )

          assert peer_event(context, request.id, "call.hangup").status == 200

        outcome when outcome in [:no_answer, :busy, :rejected] ->
          {cause, expected} =
            Keyword.fetch!(
              [
                no_answer: {"no_answer", :transfer_unanswered},
                busy: {"user_busy", :transfer_busy},
                rejected: {"call_rejected", :transfer_rejected}
              ],
              outcome
            )

          stop_transfer_room!(context.plan)
          refute_received {:test_telephony_end_leg, _}
          assert peer_event(context, request.id, "call.hangup", cause).status == 200
          assert_receive {:test_recovery_playback, "inbound-call-control", callback}, 2_000

          assert Enum.any?(
                   TelephonyHarnessBackend.operations(context.backend),
                   &match?({:caller_recovery, ^expected, _}, &1)
                 )

          refute_received {:test_telephony_end_leg, _}

          assert post_fixture(context, "call-playback-ended", %{
                   "status" => "completed",
                   "client_state" => Base.encode64(callback)
                 }).status == 200

          assert_receive {:test_telephony_end_leg,
                          %{leg: %{provider_call_control_id: "inbound-call-control"}}},
                         2_000

        :abandoned ->
          assert post_fixture(context, "call-hangup-incoming", %{
                   "call_leg_id" => "inbound-call-leg"
                 }).status == 200

          assert_receive {:test_telephony_end_leg,
                          %{leg: %{provider_call_control_id: "peer-control"}}},
                         2_000

          assert {:caller_recovery, :transfer_abandoned, request.id} in TelephonyHarnessBackend.operations(
                   context.backend
                 )

          assert peer_event(context, request.id, "call.hangup").status == 200
          refute_received {:test_recovery_playback, _, _}
      end
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, recovery_transfer: true
  test "a bridge arriving after the reconciliation deadline cannot reverse termination",
       context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_transfer_announcement, _, id}, 2_000

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_linked_dial, request}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
    %{phase: :ringing, token: ring_timer} = :sys.get_state(leg).recovery
    send(leg, {:caller_recovery_expired, ring_timer})
    %{phase: :reconciling, token: reconciliation_timer} = :sys.get_state(leg).recovery
    refute_received {:test_telephony_end_leg, _}
    send(leg, {:caller_recovery_expired, reconciliation_timer})

    assert_receive {:test_telephony_end_leg, %{leg: %{provider_call_control_id: "peer-control"}}},
                   2_000

    assert_receive {:test_telephony_end_leg,
                    %{leg: %{provider_call_control_id: "inbound-call-control"}}},
                   2_000

    assert peer_event(context, request.id, "call.bridged").status == 200
    assert peer_event(context, request.id, "call.hangup").status == 200
    refute_received {:test_linked_dial, _}
    refute_received {:test_recovery_playback, _, _}

    assert {:caller_recovery, :transfer_unknown, request.id} in TelephonyHarnessBackend.operations(
             context.backend
           )
  end

  @tag initial_outcome: :ready, caller_recovery: true, recovery_transfer: true
  test "storage loss between announcement and dial selects callback without submitting a transfer",
       context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_transfer_announcement, _, id}, 2_000
    TelephonyHarnessBackend.make_storage_unavailable(context.backend)

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_recovery_playback, "inbound-call-control", callback}, 2_000
    refute_received {:test_linked_dial, _}
    refute callback == id

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(callback)
           }).status == 200

    assert_receive {:test_telephony_end_leg,
                    %{leg: %{provider_call_control_id: "inbound-call-control"}}},
                   2_000
  end

  defp peer_event(context, id, type, cause \\ "normal_clearing"),
    do:
      post_fixture(context, "recovery-peer-event", %{
        "client_state" => ClientState.encode(id),
        "event_type" => type,
        "cause" => cause
      })

  @tag initial_outcome: :ready, caller_recovery: true, recovery_transfer: true
  test "losing the agent voice on an established call announces the configured carrier transfer",
       context do
    {_speech, _socket, voice} = start_recovery_media(context)
    TestTextToSpeechTransport.disconnect(voice, :session_failed)

    assert_receive {:test_transfer_announcement, "inbound-call-control", id}, 2_000
    refute_received {:test_linked_dial, _}

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_linked_dial, request}, 2_000
    assert request.caller == "inbound-call-control"
    refute_received {:test_transfer_announcement, _, _}
  end

  for fault <- [:recognizer_disconnected, :media_crash, :storage_outage] do
    @tag initial_outcome: :ready, caller_recovery: fault
    test "caller hears the carrier exit after #{fault}", context do
      {speech, _transport} = start_recovery_call(context)

      case unquote(fault) do
        :media_crash ->
          [{media, _}] =
            Registry.lookup(
              Vxpipe.Gateway.Media.Registry,
              {:telephony_media_session, @incoming_leg_id}
            )

          Process.exit(media, :kill)

        :storage_outage ->
          TelephonyHarnessBackend.make_storage_unavailable(context.backend)
          exhaust_recognition(speech)

        :recognizer_disconnected ->
          exhaust_recognition(speech)
      end

      assert_receive {:test_recovery_playback, "inbound-call-control", command_id}, 2_000

      assert {:caller_recovery, :announcement_requested, command_id} in TelephonyHarnessBackend.operations(
               context.backend
             )

      refute_received {:test_telephony_end_leg, _}

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64("recovery-unrelated")
             }).status == 200

      refute_received {:test_telephony_end_leg, _}

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(command_id)
             }).status == 200

      assert_receive {:test_telephony_end_leg, request}, 2_000
      assert request.leg.leg_id == @incoming_leg_id

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(command_id)
             }).status == 200

      refute_received {:test_telephony_end_leg, _}
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, command_mode: "blocked-playback"
  test "losing the playback observer waits for signed completion without replaying the clip",
       context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, _, id}, 2_000
    assert_receive {:test_playback_in_flight, http}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
    {worker, _ref} = :sys.get_state(leg).playback_worker
    monitor = Process.monitor(worker)

    try do
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
      refute_receive {:test_telephony_end_leg, _}, 250

      assert post_fixture(context, "call-playback-ended", %{
               "status" => "completed",
               "client_state" => Base.encode64(id)
             }).status == 200

      assert_receive {:test_telephony_end_leg, _}, 2_000
      refute_received {:test_recovery_playback, _, _}
      refute :sys.get_state(leg).commands_drained?
    after
      send(http, :release_playback)
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, command_mode: "blocked-playback"
  test "an ambiguous intent write consumes part of the acknowledgement budget", context do
    {speech, _} = start_recovery_call(context)
    TelephonyHarnessBackend.hold_next_journal_write(context.backend, self())
    exhaust_recognition(speech)
    assert_receive {:journal_write_in_flight, _writer, :announcement_requested}, 2_000
    assert_receive {:test_playback_in_flight, http}, 2_000

    try do
      assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
      assert Process.read_timer(:sys.get_state(leg).recovery.timer) <= 4_050
      assert_receive {:test_telephony_end_leg, _}, 5_000

      assert {:caller_recovery, :announcement_unknown, "recovery-" <> @incoming_leg_id} in TelephonyHarnessBackend.operations(
               context.backend
             )
    after
      send(http, :release_playback)
    end
  end

  for outcome <- [:rejected, :unknown] do
    @tag initial_outcome: :ready, caller_recovery: true, command_mode: "blocked-playback"
    test "carrier reports #{outcome} on the playback request", context do
      {speech, _} = start_recovery_call(context)
      exhaust_recognition(speech)
      assert_receive {:test_recovery_playback, _, id}, 2_000
      assert_receive {:test_playback_in_flight, http}, 2_000

      evidence =
        case unquote(outcome) do
          :rejected ->
            send(http, :reject_playback)
            :announcement_failed

          :unknown ->
            send(http, :unknown_playback)
            refute_receive {:test_telephony_end_leg, _}, 150

            assert post_fixture(context, "call-playback-ended", %{
                     "status" => "completed",
                     "client_state" => Base.encode64(id)
                   }).status == 200

            :announcement_completed
        end

      assert_receive {:test_telephony_end_leg, _}, 2_000

      assert {:caller_recovery, evidence, id} in TelephonyHarnessBackend.operations(
               context.backend
             )

      refute_received {:test_recovery_playback, _, _}
    end
  end

  for phase <- [:before_playback, :after_playback] do
    @tag initial_outcome: :ready, caller_recovery: true, command_mode: "blocked-playback"
    test "loss of the original leg owner #{phase} cannot recreate an effect owner", context do
      {speech, _} = start_recovery_call(context)
      assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")

      if unquote(phase) == :before_playback,
        do: TelephonyHarnessBackend.hold_next_journal_write(context.backend, self())

      exhaust_recognition(speech)

      {operation, release} =
        case unquote(phase) do
          :before_playback ->
            assert_receive {:journal_write_in_flight, writer, :announcement_requested}, 2_000
            {writer, :finish_write}

          :after_playback ->
            assert_receive {:test_recovery_playback, _, _}, 2_000
            assert_receive {:test_playback_in_flight, http}, 2_000
            {http, :release_playback}
        end

      monitor = Process.monitor(leg)
      Process.exit(leg, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^leg, :killed}, 2_000
      send(operation, release)
      # Registry may retain the dead pid until it processes its own DOWN.
      assert LegSupervisor.lookup(context.service_identity, "inbound-call-leg") in [
               {:ok, leg},
               {:error, :leg_not_found}
             ]

      refute_receive {:test_recovery_playback, _, _}, 150
      refute_received {:test_telephony_end_leg, _}

      refute Enum.any?(
               TelephonyHarnessBackend.operations(context.backend),
               &match?({:caller_recovery, :carrier_ended, _}, &1)
             )
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true, command_mode: "blocked-end"
  test "an end observer lost after send permits one same-leg retry and retains uncertain drainage",
       context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, _, id}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "completed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_telephony_end_leg, request}, 2_000
    assert_receive {:test_telephony_end_pending, first_http}, 2_000

    try do
      {worker, _} = :sys.get_state(leg).end_worker
      Process.exit(worker, :kill)
      assert_receive {:test_telephony_end_leg, ^request}, 2_000
      assert_receive {:test_telephony_end_pending, retry_http}, 2_000
      send(retry_http, :accept_test_telephony_end)

      assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
               200

      state = :sys.get_state(leg)
      assert state.carrier_ended?
      refute state.commands_drained?
      refute_received {:test_telephony_end_leg, _}
    after
      send(first_http, :accept_test_telephony_end)
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true
  test "carrier playback failure ends the call without reporting a completed prompt", context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, _, id}, 2_000

    assert post_fixture(context, "call-playback-ended", %{
             "status" => "failed",
             "client_state" => Base.encode64(id)
           }).status == 200

    assert_receive {:test_telephony_end_leg, _}, 2_000
    operations = TelephonyHarnessBackend.operations(context.backend)
    assert {:caller_recovery, :announcement_failed, id} in operations
    refute {:caller_recovery, :announcement_completed, id} in operations
  end

  @tag initial_outcome: :ready, caller_recovery: true
  test "missing carrier playback completion still ends the same leg", context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, _, _}, 2_000
    assert_receive {:test_telephony_end_leg, request}, 7_000
    assert request.reason == :speech_to_text_unavailable

    assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
             200

    assert Enum.any?(
             TelephonyHarnessBackend.operations(context.backend),
             &match?({:caller_recovery, :carrier_ended, _}, &1)
           )
  end

  @tag initial_outcome: :ready, caller_recovery: true
  test "caller hangup while a recovery recording plays retires the announcement", context do
    {speech, _} = start_recovery_call(context)
    exhaust_recognition(speech)
    assert_receive {:test_recovery_playback, _, _}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")
    ref = Process.monitor(leg)

    assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
             200

    assert_receive {:DOWN, ^ref, :process, ^leg, :normal}, 2_000
    refute_received {:test_telephony_end_leg, _}
  end

  for loss <- [:room_shutdown, :platform_hangup] do
    @tag initial_outcome: :ready, caller_recovery: true
    test "carrier playback observes #{loss} after taking ownership", context do
      {speech, _} = start_recovery_call(context)
      exhaust_recognition(speech)
      assert_receive {:test_recovery_playback, _, command_id}, 2_000

      [{room, _}] =
        Registry.lookup(
          Vxpipe.CallEngine.RoomRegistry,
          {context.plan.tenant_id, context.plan.room_id}
        )

      monitor = Process.monitor(room)

      case unquote(loss) do
        :room_shutdown ->
          stop_room(context.plan.tenant_id, context.plan.room_id)

        :platform_hangup ->
          call = TelephonyHarnessBackend.claim(context.backend).call

          assert :ok =
                   Vxpipe.CallEngine.hangup_call(
                     call.tenant_key,
                     call.room_id,
                     call.incarnation_id
                   )
      end

      assert_receive {:DOWN, ^monitor, :process, ^room, _reason}, 2_000

      if unquote(loss) == :room_shutdown do
        refute_received {:test_telephony_end_leg, _}

        assert post_fixture(context, "call-playback-ended", %{
                 "status" => "completed",
                 "client_state" => Base.encode64(command_id)
               }).status == 200
      end

      assert_receive {:test_telephony_end_leg, _}, 2_000
    end
  end

  @tag initial_outcome: :ready, caller_recovery: true
  test "a busy leg cannot stall media teardown or lose the queued failure", context do
    {speech, _} = start_recovery_call(context)
    assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")

    [{media, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, @incoming_leg_id})

    monitor = Process.monitor(media)
    :ok = :sys.suspend(leg)

    try do
      exhaust_recognition(speech)
      assert_receive {:DOWN, ^monitor, :process, ^media, :media_unavailable}, 1_000
    after
      :sys.resume(leg)
    end

    assert_receive {:test_recovery_playback, _, _}, 2_000
  end

  for outcome <- [:ready, :model, :readiness, :max_duration, :disconnected] do
    @tag initial_outcome: outcome
    test "initial phone startup handles #{outcome} under its original clocks", context do
      outcome = context.initial_outcome
      assert post_fixture(context, "call-initiated-incoming").status == 200
      assert_receive {:test_telephony_answer, answer}, 2_000
      assert post_fixture(context, "call-answered-incoming").status == 200
      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
      preparation_monitor = Process.monitor(preparer)

      [{authority, _}] =
        Registry.lookup(
          Vxpipe.CallEngine.RoomRegistry,
          {context.plan.tenant_id, context.plan.room_id}
        )

      room_monitor = Process.monitor(authority)

      transport =
        start_supervised!(
          Supervisor.child_spec({TestTelephonySocket, observer: self()}, restart: :temporary),
          id: :initial_phone_socket
        )

      transport_monitor = Process.monitor(transport)

      assert {:ok, _binding, _socket} =
               TestTelephonySocket.open(transport, TelephonyMediaSocket, fn ->
                 TelnyxFixture.open_media(context.endpoint, answer.media_url, %{
                   "call_control_id" => "inbound-call-control",
                   "call_session_id" => "inbound-call-session",
                   "client_state" => ClientState.encode(@incoming_leg_id),
                   "from" => "+15550001001",
                   "stream_id" => "inbound-stream",
                   "to" => "+15550001000"
                 })
               end)

      if outcome in [:max_duration, :disconnected] do
        refute_receive {:test_phone_output, ^transport, _}, 150
      else
        assert_phone_wait(transport, System.monotonic_time(:millisecond) + 2_000)
      end

      assert Vxpipe.CallEngine.RoomAuthority.input_admission(
               context.plan.tenant_id,
               context.plan.room_id
             ) == :opening_audio

      refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
      refute_receive {:test_call_lifecycle_timer_scheduled, _, 15_000}

      case outcome do
        :ready ->
          send(preparer, :release_test_agent_runtime_model)
          assert_receive {:test_tts_transport_started, voice, _}, 2_000
          assert_receive {:test_stt_transport_started, speech, _}, 2_000

          TestTextToSpeechTransport.deliver_control(
            voice,
            ~s({"type":"Connected","request_id":"phone-voice-ready"})
          )

          assert_phone_wait(transport, System.monotonic_time(:millisecond) + 2_000)
          refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

          TestSpeechToTextTransport.deliver(
            speech,
            ~s({"type":"Connected","request_id":"phone-speech-ready","sequence_id":0})
          )

          Vxpipe.CallEngine.TestCallStartup.await_open(context.plan)
          assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}, 2_000
          refute_receive {:test_call_lifecycle_timer_cancelled, ^maximum_timer}
          refute_receive {:test_tts_transport_started, _, _}
          refute_receive {:test_stt_transport_started, _, _}
          assert_caller_audio(speech, transport)

        :model ->
          send(preparer, :release_test_agent_runtime_model)

        :readiness ->
          Vxpipe.CallEngine.TestCallLifecycleTimer.fire(readiness_timer)

        :max_duration ->
          Vxpipe.CallEngine.TestCallLifecycleTimer.fire(maximum_timer)

        :disconnected ->
          stop_supervised!(:initial_phone_socket)
      end

      if outcome != :ready do
        assert_receive {:DOWN, ^room_monitor, :process, ^authority, _}, 2_000
        assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 2_000
        assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
        assert_receive {:test_telephony_end_leg, request}, 2_000
        assert request.leg.leg_id == @incoming_leg_id
        assert request.reason == :room_ended
        refute_receive {:test_telephony_end_leg, _duplicate}
        refute_receive {:test_tts_transport_started, _, _}
        refute_receive {:test_call_lifecycle_timer_scheduled, _, 15_000}
      end
    end
  end

  for outcome <- [:model, :readiness, :max_duration] do
    @tag initial_outcome: outcome
    test "initial phone #{outcome} ends the answered leg before a media socket connects",
         context do
      assert post_fixture(context, "call-initiated-incoming").status == 200
      assert_receive {:test_telephony_answer, _answer}, 2_000
      assert post_fixture(context, "call-answered-incoming").status == 200

      assert {:ok, leg} = LegSupervisor.lookup(context.service_identity, "inbound-call-leg")

      monitor = Process.monitor(leg)
      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
      preparation_monitor = Process.monitor(preparer)

      case unquote(outcome) do
        :model -> send(preparer, :release_test_agent_runtime_model)
        :readiness -> Vxpipe.CallEngine.TestCallLifecycleTimer.fire(readiness_timer)
        :max_duration -> Vxpipe.CallEngine.TestCallLifecycleTimer.fire(maximum_timer)
      end

      assert_receive {:test_telephony_end_leg, request}, 2_000
      assert request.leg.leg_id == @incoming_leg_id
      assert request.reason == :room_ended
      refute_received {:DOWN, ^monitor, :process, ^leg, _}

      assert post_fixture(context, "call-hangup-incoming", %{"call_leg_id" => "inbound-call-leg"}).status ==
               200

      assert_receive {:DOWN, ^monitor, :process, ^leg, _}, 2_000
      assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 2_000
      refute_receive {:test_telephony_end_leg, _duplicate}
      refute_receive {:test_tts_transport_started, _, _}
    end
  end

  defp assert_phone_wait(transport, deadline) do
    receive do
      {:test_phone_output, ^transport, output} ->
        case JSON.decode!(output) do
          %{"event" => "media", "media" => %{"payload" => payload}} ->
            assert byte_size(Base.decode64!(payload)) > 0

          _control ->
            assert_phone_wait(transport, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("missing phone setup waiting")
    end
  end

  for {mode, loss} <- [
        {:defaults, nil},
        {:custom_url, nil},
        {:silent_all, nil},
        {:custom_url, :destination},
        {:silent_all, :cue}
      ] do
    @tag transfer_wait_mode: mode, phone_loss: loss
    test "runs one signed inbound call through private press-1 phone transfer after storage loss with #{mode} waits #{loss || :ready}",
         context do
      incoming = post_fixture(context, "call-initiated-incoming")
      assert incoming.status == 200
      assert post_fixture(context, "call-answered-incoming").status == 200

      assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      assert_receive {:test_telephony_answer, answer}, 2_000
      refute_receive {:test_telephony_answer, _duplicate}

      duplicate = post_fixture(context, "call-initiated-incoming")
      assert duplicate.status == 200
      refute_receive {:test_telephony_answer, _duplicate}

      :ok = TelephonyHarnessBackend.make_storage_unavailable(context.backend)

      answered = post_fixture(context, "call-answered-incoming")
      assert answered.status == 200

      inbound_transport =
        start_supervised!({TestTelephonySocket, observer: self()}, id: :incoming_socket)

      outbound_transport =
        start_supervised!({TestTelephonySocket, observer: self()}, id: :outgoing_socket)

      assert {:ok, inbound_binding, inbound_socket} =
               TestTelephonySocket.open(inbound_transport, TelephonyMediaSocket, fn ->
                 TelnyxFixture.open_media(context.endpoint, answer.media_url, %{
                   "call_control_id" => "inbound-call-control",
                   "call_session_id" => "inbound-call-session",
                   "client_state" => ClientState.encode(@incoming_leg_id),
                   "from" => "+15550001001",
                   "stream_id" => "inbound-stream",
                   "to" => "+15550001000"
                 })
               end)

      assert inbound_binding.client_state_leg_id == @incoming_leg_id

      assert {:ok, %{attachment: %{admission: :main}}} =
               MediaSupervisor.snapshot(@incoming_leg_id)

      assert_receive {:test_stt_transport_started, stt_transport, _connection}, 2_000

      begin_transfer(stt_transport, inbound_transport, context.plan)

      assert_receive {:test_telephony_dial, dial}, 2_000
      assert dial.leg_id == @outgoing_leg_id
      assert dial.to == "+15550001002"

      outgoing_client_state = ClientState.encode(@outgoing_leg_id)

      assert post_fixture(context, "call-initiated-outgoing", %{
               "client_state" => outgoing_client_state
             }).status == 200

      assert post_fixture(context, "call-initiated-outgoing", %{
               "client_state" => outgoing_client_state
             }).status == 200

      refute_receive {:test_telephony_dial, _duplicate}

      assert {:ok, _outbound_binding, _outbound_socket} =
               TestTelephonySocket.open(outbound_transport, TelephonyMediaSocket, fn ->
                 TelnyxFixture.open_media(context.endpoint, dial.media_url, %{
                   "call_control_id" => "outbound-call-control",
                   "call_session_id" => "outbound-call-session",
                   "client_state" => outgoing_client_state,
                   "from" => "+15550001000",
                   "stream_id" => "outbound-stream",
                   "to" => "+15550001002"
                 })
               end)

      assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

      TestTextToSpeechTransport.deliver_control(
        briefing_tts,
        ~s({"type":"Connected","request_id":"briefing-ready"})
      )

      await_transfer_preparation(context.plan, System.monotonic_time(:millisecond) + 2_000)

      assert {:ok, _outbound_socket} =
               TestTelephonySocket.input(
                 outbound_transport,
                 {TelnyxFixture.body("media-dtmf", %{
                    "digit" => "1",
                    "stream_id" => "outbound-stream"
                  }), opcode: :text}
               )

      assert {:ok, %{attachment: %{admission: :transfer_preparation}}} =
               MediaSupervisor.snapshot(@outgoing_leg_id)

      reception = Map.fetch!(context.plan.participants, "reception")

      [{source_agent, _value}] =
        Registry.lookup(
          Vxpipe.CallEngine.RoomRegistry,
          {:participant, context.plan.tenant_id, context.plan.room_id, reception.participant_id}
        )

      source_monitor = Process.monitor(source_agent)
      finish_private_briefing(briefing_tts)

      assert {:ok, %{transfer_acceptance_ready?: true}} = await_transfer_state(:acceptance_ready)

      assert {:ok, _socket} =
               TestTelephonySocket.input(
                 outbound_transport,
                 {TelnyxFixture.body("media-dtmf", %{
                    "digit" => "1",
                    "stream_id" => "outbound-stream",
                    "sequence_number" => 100
                  }), opcode: :text}
               )

      assert_receive {:test_stt_transport_started, support_stt, _}, 2_000

      proof =
        Vxpipe.Gateway.PhoneHandoffAssertions.gate(
          :telnyx,
          context.plan,
          {context.transfer_wait_mode, context.phone_loss},
          inbound_transport,
          outbound_transport,
          stt_transport,
          support_stt,
          {@incoming_leg_id, @outgoing_leg_id}
        )

      if context.phone_loss do
        Vxpipe.Gateway.PhoneHandoffAssertions.recovery(proof, source_tts)
        refute_receive {:DOWN, ^source_monitor, :process, ^source_agent, _}, 0
      else
        assert_receive {:DOWN, ^source_monitor, :process, ^source_agent, _reason}, 2_000

        assert {:ok, %{attachment: %{admission: :main}}} = await_transfer_state(:main)

        caller = Map.fetch!(context.plan.participants, "caller")
        support = Map.fetch!(context.plan.participants, "human-support")

        assert {:ok, caller_snapshot} =
                 Vxpipe.CallEngine.participant_snapshot(
                   context.plan.tenant_id,
                   context.plan.room_id,
                   caller.participant_id
                 )

        assert {:ok, support_snapshot} =
                 Vxpipe.CallEngine.participant_snapshot(
                   context.plan.tenant_id,
                   context.plan.room_id,
                   support.participant_id
                 )

        assert caller_snapshot.state == :joined
        assert support_snapshot.state == :joined
        Vxpipe.Gateway.PhoneHandoffAssertions.conversation(proof)
      end

      claim_count =
        Enum.count(TelephonyHarnessBackend.operations(context.backend), fn
          {:claim_incoming, _event_id} -> true
          _operation -> false
        end)

      assert claim_count == 1
      assert inbound_socket.stream_id == "inbound-stream"
    end
  end

  defp post_fixture(context, name, replacements \\ %{}) do
    TelnyxFixture.post_event(
      context.endpoint,
      context.private_key,
      context.plan.tenant_id,
      name,
      replacements,
      @received_at
    )
  end

  defp begin_transfer(stt_transport, socket, plan) do
    TestSpeechToTextTransport.deliver(
      stt_transport,
      ~s({"type":"Connected","request_id":"request-telnyx-harness","sequence_id":0})
    )

    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    assert_caller_audio(stt_transport, socket)

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("StartOfTurn", 1, "Please connect me to human support.")
    )

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("EndOfTurn", 2, "Please connect me to human support.", "model")
    )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "phone-transfer",
               name: "transfer",
               arguments: %{
                 "destination" => "human-support",
                 "reason" => "Taylor is calling about order 17."
               }
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _}, 2_000
    assert {:ok, acknowledgement} = ModelResponse.new(text: "Connecting support.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, acknowledgement}})
  end

  defp exhaust_recognition(speech) do
    GenServer.stop(speech, :normal)
    assert_receive {:scribe_started, replacement}, 2_000
    GenServer.stop(replacement, :normal)
  end

  defp start_recovery_call(context) do
    {speech, transport, _voice} = start_recovery_media(context)
    {speech, transport}
  end

  defp start_recovery_media(context) do
    assert post_fixture(context, "call-initiated-incoming").status == 200
    assert_receive {:test_telephony_answer, answer}, 2_000
    assert post_fixture(context, "call-answered-incoming").status == 200
    assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000

    transport =
      start_supervised!(
        Supervisor.child_spec({TestTelephonySocket, observer: self()}, restart: :temporary)
      )

    assert {:ok, _binding, _socket} =
             TestTelephonySocket.open(transport, TelephonyMediaSocket, fn ->
               TelnyxFixture.open_media(context.endpoint, answer.media_url, %{
                 "call_control_id" => "inbound-call-control",
                 "call_session_id" => "inbound-call-session",
                 "client_state" => ClientState.encode(@incoming_leg_id),
                 "from" => "+15550001001",
                 "stream_id" => "inbound-stream",
                 "to" => "+15550001000"
               })
             end)

    send(preparer, :release_test_agent_runtime_model)
    assert_receive {:test_tts_transport_started, voice, _}, 2_000
    assert_receive {:scribe_started, speech}, 2_000

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"Connected","request_id":"phone-voice-ready"})
    )

    Vxpipe.CallEngine.TestElevenLabsScribeTransport.deliver(speech, {:ready, "qa-call"})
    Vxpipe.CallEngine.TestCallStartup.await_open(context.plan)
    {speech, transport, voice}
  end

  defp assert_caller_audio(stt_transport, socket) do
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)

    assert {:ok, payload} =
             Membrane.Opus.Encoder.Native.encode_packet(
               encoder,
               :binary.copy(<<0::16>>, 320),
               320
             )

    message = %{
      "event" => "media",
      "stream_id" => "inbound-stream",
      "sequence_number" => 2,
      "media" => %{
        "track" => "inbound",
        "chunk" => 1,
        "timestamp" => 0,
        "payload" => Base.encode64(payload)
      }
    }

    assert {:ok, _socket} =
             TestTelephonySocket.input(socket, {JSON.encode!(message), opcode: :text})

    assert_receive {:test_stt_audio, ^stt_transport, ^payload}, 2_000
  end

  defp turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-telnyx-harness",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    JSON.encode!(message)
  end

  defp finish_private_briefing(briefing_tts) do
    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(
      briefing_tts,
      :binary.copy(<<1_000::little-signed-16>>, 960)
    )

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )
  end

  defp stop_transfer_room!(plan) do
    [{room, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    monitor = Process.monitor(room)
    Process.exit(room, :shutdown)
    assert_receive {:DOWN, ^monitor, :process, ^room, _}, 2_000
  end

  defp stop_room(tenant_id, room_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}) do
      [{room, _value}] -> Process.exit(room, :shutdown)
      [] -> :ok
    end
  end

  defp await_transfer_state(expected) do
    await_transfer_state(expected, System.monotonic_time(:millisecond) + 2_000)
  end

  defp await_transfer_state(expected, deadline) do
    result = MediaSupervisor.snapshot(@outgoing_leg_id)

    ready? =
      case {expected, result} do
        {:main, {:ok, %{attachment: %{admission: :main}}}} -> true
        {:acceptance_ready, {:ok, %{transfer_acceptance_ready?: true}}} -> true
        _pending -> false
      end

    if ready? or System.monotonic_time(:millisecond) >= deadline do
      result
    else
      receive do
      after
        10 -> await_transfer_state(expected, deadline)
      end
    end
  end

  defp await_transfer_preparation(plan, deadline) do
    [{authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    case :sys.get_state(authority).pending_participant_transfer do
      %{preparation: preparation} when not is_nil(preparation) ->
        :ok

      _pending ->
        assert System.monotonic_time(:millisecond) < deadline,
               "transfer preparation did not finish after private text-to-speech became ready"

        receive do
        after
          10 -> await_transfer_preparation(plan, deadline)
        end
    end
  end
end
