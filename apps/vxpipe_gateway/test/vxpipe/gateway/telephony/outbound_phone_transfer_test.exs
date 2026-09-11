defmodule Vxpipe.Gateway.Telephony.OutboundPhoneTransferTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    ConnectionAttachment,
    DefinitionCompiler,
    TestAudioOutputSink,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.Telephony.{EndLeg, Event, LegReference}

  alias Vxpipe.Gateway.Telephony.{
    LegSupervisor,
    MediaAdmission,
    MediaSupervisor,
    OutgoingLeg,
    OutgoingLegConnector,
    ServiceRegistry
  }

  alias Vxpipe.Gateway.TestTelephonySocket

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestSelectiveAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-test-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, observer: self()},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "the exact outbound phone leg accepts with press 1 after its private briefing" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    leg_id = unique_id("outbound-leg")
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    registry =
      ServiceRegistry.init!(enabled: true, services: [service(plan.tenant_id, self())])

    connector =
      {OutgoingLegConnector,
       [
         leg_id: fn -> leg_id end,
         leg_supervisor: LegSupervisor,
         media_admission: MediaAdmission,
         media_supervisor: MediaSupervisor,
         service_registry: registry
       ]}

    assert {:ok, room} = CallEngine.start_call(plan, outbound_leg_connector: connector)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :outbound_phone_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller)

    assert_receive {:test_telephony_dial, %{leg_id: ^leg_id}}, 2_000
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(leg_id)

    socket = start_supervised!({TestTelephonySocket, observer: self()})

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(leg, media_started_event(leg_id), 5_000)
             end)

    assert {:ok,
            %{
              attachment: %ConnectionAttachment{
                admission: :transfer_preparation,
                room_audio_input_mode: :disabled,
                room_audio_output_mode: :disabled,
                transfer_attempt_id: attempt_id
              }
            }} = MediaSupervisor.snapshot(leg_id)

    assert is_binary(attempt_id)
    assert_receive {:test_tts_control, ^briefing_tts, speak}, 2_000

    assert JSON.decode!(speak) == %{
             "text" => "Taylor is calling about order 17. This call is recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    assert {:error, :wrong_media_source} =
             OutgoingLeg.dispatch(leg, dtmf_event(leg_id, "1"), 5_000)

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(leg, dtmf_event(leg_id, "1"), 5_000)
             end)

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "phone-transfer"}}, 50

    finish_private_briefing(briefing_tts)

    assert_receive {:test_telnyx_socket_send, message}, 2_000
    assert %{"event" => "media"} = JSON.decode!(message)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "phone-transfer",
                      result: %{
                        "destination" => "human-support",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert_eventually(fn ->
      match?(
        {:ok,
         %{
           attachment: %ConnectionAttachment{
             admission: :main,
             room_audio_input_mode: :enabled,
             room_audio_output_mode: :mix_minus
           },
           room_audio_ingress: ingress,
           room_audio_egress: egress
         }}
        when is_pid(ingress) and is_pid(egress),
        MediaSupervisor.snapshot(leg_id)
      )
    end)

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(leg, dtmf_event(leg_id, "1"), 5_000)
             end)

    assert {:ok, snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert snapshot.participant_id == support.participant_id
  end

  test "a configured machine result ends only the attempted destination and retains the source" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    leg_id = unique_id("outbound-machine-leg")
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    registry =
      ServiceRegistry.init!(
        enabled: true,
        services: [service(plan.tenant_id, self(), answering_machine_detection: :detect)]
      )

    connector =
      {OutgoingLegConnector,
       [
         leg_id: fn -> leg_id end,
         leg_supervisor: LegSupervisor,
         media_admission: MediaAdmission,
         media_supervisor: MediaSupervisor,
         service_registry: registry
       ]}

    assert {:ok, room} = CallEngine.start_call(plan, outbound_leg_connector: connector)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :machine_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller)

    assert_receive {:test_telephony_dial,
                    %{leg_id: ^leg_id, answering_machine_detection: :detect}},
                   2_000

    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(leg_id)
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(), 1_000)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{leg_id: ^leg_id},
                      reason: :answering_machine
                    }},
                   2_000

    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{tool_call_id: "phone-transfer", reason: :tool_failed}},
                   2_000

    assert {:ok, source} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert source.participant_id == reception.participant_id
    refute_receive {:test_telephony_end_leg, _duplicate}
  end

  defp compile_plan do
    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "start_call"
                     }
                   },
                   "reception" => %{
                     type: "agent",
                     prompt: "Route callers safely.",
                     capabilities: %{
                       model_inference: "test-model",
                       text_to_speech: "test-voice"
                     },
                     tools: %{},
                     transfers: ["human-support"]
                   },
                   "human-support" => %{
                     type: "human",
                     description: "A human support specialist",
                     connection: %{
                       service: "primary-phone",
                       mode: "dial",
                       number: "+15550001001"
                     },
                     transfer_notice: "This call is recorded."
                   }
                 },
                 transfer_policy: %{attempt_timeout_ms: 10_000},
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "outbound-phone-transfer-definition",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "outbound-phone-transfer-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-outbound-phone",
               actor_id: "actor-outbound-phone",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{
                 "test-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: "test:scripted"}
                 },
                 "test-voice" => %{
                   kind: :text_to_speech,
                   provider: FluxTextToSpeech,
                   options: %{
                     model: "flux-test-voice",
                     encoding: :linear16,
                     sample_rate: 48_000
                   }
                 }
               },
               host_tools: %{}
             })

    plan
  end

  defp begin_transfer(plan, room, caller) do
    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "Please connect me to human support.")
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
  end

  defp attach(plan, room, participant, connection_id, output_sink) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    CallEngine.attach_connection(command, output_sink)
  end

  defp send_command(plan, room, caller, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "caller-connection",
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp media_started_event(leg_id) do
    %Event{
      kind: :media_started,
      provider: :telnyx,
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      stream_id: "outbound-stream"
    }
  end

  defp dtmf_event(leg_id, digit) do
    %Event{
      kind: :dtmf,
      provider: :telnyx,
      provider_event_id: unique_id("event"),
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      digit: digit,
      occurred_at: DateTime.utc_now()
    }
  end

  defp answering_machine_event do
    %Event{
      kind: :answering_machine,
      provider: :telnyx,
      provider_event_id: unique_id("event"),
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      answering_machine: :machine,
      occurred_at: DateTime.utc_now()
    }
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

  defp service(tenant_id, observer, overrides \\ []) do
    Keyword.merge(
      [
        id: "primary-phone",
        ingress_key: "outbound_ingress",
        scope: {:tenant, tenant_id},
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

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      receive do
      after
        10 -> assert_eventually(assertion, attempts - 1)
      end
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
