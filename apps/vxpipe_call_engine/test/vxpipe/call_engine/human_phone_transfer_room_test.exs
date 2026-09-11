defmodule Vxpipe.CallEngine.HumanPhoneTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    ConnectionAttachment,
    DefinitionCompiler,
    TestAudioOutputSink,
    TestOutboundLegConnector,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl, SendText}
  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Event.ToolCallFailed
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.Telephony.{OutboundLegRequest, OutboundLegRequestResolver}

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

  test "a protected phone destination opens one exact outbound leg before private handoff" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, %OutboundLegRequest{to: "+15550001001"}} =
             OutboundLegRequestResolver.resolve(plan, support, "rinc-probe")

    assert {:ok, room} =
             CallEngine.start_call(plan,
               outbound_leg_connector: {TestOutboundLegConnector, self()}
             )

    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :phone_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :phone_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "phone-transfer")

    assert_receive {:test_outbound_leg_connect, connector_task,
                    %OutboundLegRequest{
                      tenant_id: tenant_id,
                      actor_id: actor_id,
                      call_id: call_id,
                      room_id: room_id,
                      incarnation_id: incarnation_id,
                      participant_id: participant_id,
                      service_id: "primary-phone",
                      to: "+15550001001",
                      answering_machine_detection: :disabled
                    }, timeout},
                   2_000

    assert is_pid(connector_task)
    assert tenant_id == plan.tenant_id
    assert actor_id == plan.actor_id
    assert call_id == plan.call_id
    assert room_id == plan.room_id
    assert incarnation_id == room.incarnation_id
    assert participant_id == support.participant_id
    assert timeout > 0
    assert timeout <= 30_000

    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "phone-leg", support_sink)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    finish_private_briefing(briefing_tts, support_sink)

    assert_receive {:vxpipe_transfer_main_media, ^attempt_id,
                    %ConnectionAttachment{admission: :main}},
                   2_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "phone-transfer",
                      result: %{
                        "destination" => "human-support",
                        "status" => "completed"
                      }
                    }},
                   2_000

    refute_receive {:test_outbound_leg_disconnect, _process, _reference}, 50
  end

  test "an unanswered phone destination is disconnected at the original transfer deadline" do
    plan = compile_plan(transfer_timeout_ms: 1_000)
    caller = Map.fetch!(plan.participants, "caller")

    assert {:ok, room} =
             CallEngine.start_call(plan,
               outbound_leg_connector: {TestOutboundLegConnector, self()}
             )

    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :deadline_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "deadline-phone-transfer")

    assert_receive {:test_outbound_leg_connect, _connector_task, request, timeout}, 2_000
    assert request.to == "+15550001001"
    assert timeout > 0
    assert timeout <= 1_000
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "deadline-phone-transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_receive {:test_outbound_leg_disconnect, _cleanup_task, participant_id}, 2_000
    assert participant_id == request.participant_id
  end

  test "losing the exact outbound owner fails the pending transfer and retains the source" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")

    owner =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :failed_outbound_phone_owner
      )

    connector =
      {TestOutboundLegConnector,
       %{
         observer: self(),
         owner: owner
       }}

    assert {:ok, room} = CallEngine.start_call(plan, outbound_leg_connector: connector)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :owner_loss_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "owner-loss-phone-transfer")

    assert_receive {:test_outbound_leg_connect, _connector_task, request, _timeout}, 2_000
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    monitor = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "owner-loss-phone-transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_receive {:test_outbound_leg_disconnect, _cleanup_task, participant_id}, 2_000
    assert participant_id == request.participant_id

    assert {:ok, source} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert source.participant_id == reception.participant_id
  end

  defp compile_plan(options \\ []) do
    transfer_timeout_ms = Keyword.get(options, :transfer_timeout_ms, 30_000)

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 call_variables: %{
                   sections: %{
                     "routing" => %{
                       schema: %{
                         "type" => "object",
                         "properties" => %{
                           "support_number" => %{"type" => ["string", "null"]}
                         },
                         "additionalProperties" => false
                       }
                     }
                   }
                 },
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
                       number_from_variable: %{
                         section: "routing",
                         variable: "support_number"
                       }
                     },
                     transfer_notice: "This call is recorded."
                   }
                 },
                 transfer_policy: %{attempt_timeout_ms: transfer_timeout_ms},
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "phone-transfer-definition",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "phone-transfer-definition", revision: 1},
                 initial_variables: %{
                   "routing" => %{"support_number" => "+15550001001"}
                 },
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-phone-transfer",
               actor_id: "actor-phone-transfer",
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

  defp begin_transfer(plan, room, caller, tool_call_id) do
    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "Please connect me to human support.")
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: tool_call_id,
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

  defp transfer_control(plan, room, participant, attempt_id, action) do
    assert {:ok, command} =
             ParticipantTransferControl.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "phone-leg",
               attempt_id: attempt_id,
               action: action,
               deadline: future_deadline()
             )

    command
  end

  defp finish_private_briefing(briefing_tts, support_sink) do
    assert_receive {:test_tts_control, ^briefing_tts, _speak}, 2_000
    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(briefing_tts, <<1, 0, 2, 0>>)

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )

    assert_receive {:test_audio_output, ^support_sink, _frame}, 2_000
    assert_receive {:test_audio_output_finish, ^support_sink, _turn}, 2_000
    assert :ok = TestAudioOutputSink.playback_started(support_sink)
    assert :ok = TestAudioOutputSink.playback_completed(support_sink)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
