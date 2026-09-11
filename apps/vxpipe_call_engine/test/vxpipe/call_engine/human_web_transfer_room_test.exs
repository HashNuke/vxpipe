defmodule Vxpipe.CallEngine.HumanWebTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallDefinition,
    CallInvocation,
    CallVariables,
    ConnectionAttachment,
    DefinitionCompiler,
    RoomMixer,
    TestAudioOutputSink,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech

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

  test "an exact web destination hears its private briefing before promotion" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    variables = CallVariables.whereis(room.incarnation_id)
    lifecycle = call_lifecycle(room.incarnation_id)

    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :caller_output_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :support_output_sink)

    assert {:ok,
            %ConnectionAttachment{
              admission: :main,
              room_audio_input_mode: :enabled,
              room_audio_output_mode: :mix_minus
            }} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    source_supervisor = participant_supervisor(plan, reception.participant_id)
    source_monitor = Process.monitor(source_supervisor)

    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "Please connect me to human support.")
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    reason = "Taylor is calling about order 17."

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "human-support-transfer",
               name: "transfer",
               arguments: %{"destination" => "human-support", "reason" => reason}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              room_audio_input_mode: :disabled,
              room_audio_output_mode: :disabled,
              transfer_attempt_id: attempt_id
            } = pending_attachment} =
             attach(plan, room, support, "support-connection", support_sink)

    assert is_binary(attempt_id)
    assert :disabled = CallEngine.room_audio_configuration(pending_attachment)
    assert :disabled = CallEngine.room_audio_output_configuration(pending_attachment)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                   50

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    assert_receive {:test_tts_control, ^briefing_tts, speak}, 2_000

    assert JSON.decode!(speak) == %{
             "text" => reason <> " This call is recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(briefing_tts, <<1, 0, 2, 0>>)

    assert_receive {:test_audio_output, ^support_sink, _frame}, 2_000
    refute_receive {:test_audio_output, ^caller_sink, _frame}, 50

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )

    assert_receive {:test_audio_output_finish, ^support_sink, _turn}, 2_000

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                   50

    assert :ok = TestAudioOutputSink.playback_started(support_sink)
    assert :ok = TestAudioOutputSink.playback_completed(support_sink)

    assert_receive {:vxpipe_transfer_main_media, ^attempt_id,
                    %ConnectionAttachment{
                      admission: :main,
                      room_audio_input_mode: :enabled,
                      room_audio_output_mode: :mix_minus
                    }},
                   2_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "human-support-transfer",
                      result: %{
                        "destination" => "human-support",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert_receive {:DOWN, ^source_monitor, :process, ^source_supervisor, _reason}, 2_000

    assert {:ok, support_snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert support_snapshot.participant_id == support.participant_id
    assert CallVariables.whereis(room.incarnation_id) == variables
    assert call_lifecycle(room.incarnation_id) == lifecycle
    assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == nil
  end

  test "only the exact destination connection can control the current attempt" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "controlled-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    stale =
      transfer_control(plan, room, support, "xfer_stale_attempt", :accept)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(stale)

    forged_actor =
      transfer_control(plan, room, support, attempt_id, :accept, actor_id: "another-actor")

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(forged_actor)

    exact = transfer_control(plan, room, support, attempt_id, :accept)

    foreign_connection =
      start_supervised!({Agent, fn -> :ready end}, id: :foreign_transfer_connection)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             Agent.get(foreign_connection, fn :ready ->
               CallEngine.participant_transfer_control(exact)
             end)

    assert :ok = CallEngine.participant_transfer_control(exact)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(exact)

    ready = transfer_control(plan, room, support, attempt_id, :media_ready)
    assert :ok = CallEngine.participant_transfer_control(ready)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(ready)
  end

  test "a dropped private destination fails only that attempt" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "dropped-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    support_connection =
      start_supervised!({Agent, fn -> :ready end}, id: :dropping_transfer_connection)

    command = attachment_command(plan, room, support, "support-connection")

    assert {:ok, %ConnectionAttachment{admission: :transfer_preparation}} =
             Agent.get(support_connection, fn :ready ->
               CallEngine.attach_connection(command, support_sink)
             end)

    assert :ok = stop_supervised(:dropping_transfer_connection)

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "dropped-human-transfer",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   2_000

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "dropped-human-transfer"}},
                   50

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               support.participant_id
             )
  end

  test "a timed-out destination cannot use late readiness to join main media" do
    plan = compile_plan(transfer_timeout_ms: 1_000)
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "timed-out-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "timed-out-human-transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_receive {:vxpipe_connection_unavailable, :transfer_failed}, 2_000

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _attachment}, 50

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "timed-out-human-transfer"}},
                   50

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               support.participant_id
             )
  end

  @tag capture_log: true
  test "a failed privacy barrier closes the room before bridge or source handoff" do
    plan =
      compile_plan(
        support_while_present: %{
          audio_routes: %{
            "caller" => ["human-support"],
            "human-support" => ["caller"]
          },
          transcript_routes: %{},
          record_audio: false,
          save_transcripts: false
        }
      )

    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    room_monitor = Process.monitor(room_authority)

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "policy-failed-human-transfer")
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    force_future_mixer_revision(room.incarnation_id)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    finish_private_briefing(briefing_tts, support_sink)

    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _attachment}, 50

    refute_receive {:vxpipe_event,
                    %ToolCallCompleted{tool_call_id: "policy-failed-human-transfer"}},
                   50
  end

  defp compile_plan(options \\ []) do
    transfer_timeout_ms = Keyword.get(options, :transfer_timeout_ms, 30_000)

    support = %{
      type: "human",
      description: "A human support specialist",
      connection: %{
        service: "web",
        mode: "receive",
        admission: "transfer"
      },
      transfer_notice: "This call is recorded."
    }

    support =
      case Keyword.get(options, :support_while_present) do
        nil -> support
        policy -> Map.put(support, :while_present, policy)
      end

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 transfer_policy: %{attempt_timeout_ms: transfer_timeout_ms},
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
                   "human-support" => support
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "human-transfer-definition",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "human-transfer-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-transfer",
               actor_id: "actor-human-transfer",
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

  defp attach(plan, room, participant, connection_id, output_sink) do
    command = attachment_command(plan, room, participant, connection_id)
    CallEngine.attach_connection(command, output_sink)
  end

  defp attachment_command(plan, room, participant, connection_id) do
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

    command
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

  defp transfer_control(plan, room, participant, attempt_id, action, overrides \\ []) do
    assert {:ok, command} =
             ParticipantTransferControl.new(
               Keyword.merge(
                 [
                   tenant_id: plan.tenant_id,
                   actor_id: plan.actor_id,
                   room_id: plan.room_id,
                   incarnation_id: room.incarnation_id,
                   participant_id: participant.participant_id,
                   connection_id: "support-connection",
                   attempt_id: attempt_id,
                   action: action,
                   deadline: future_deadline()
                 ],
                 overrides
               )
             )

    command
  end

  defp participant_supervisor(plan, participant_id) do
    assert [{supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant_supervisor, plan.tenant_id, plan.room_id, participant_id}
             )

    supervisor
  end

  defp call_lifecycle(incarnation_id) do
    assert [{lifecycle, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:call_lifecycle, incarnation_id}
             )

    lifecycle
  end

  defp force_future_mixer_revision(incarnation_id) do
    incarnation_id
    |> RoomMixer.whereis()
    |> :sys.replace_state(fn state ->
      policy = %{state.policy | revision: state.policy.revision + 100}
      %{state | policy: policy}
    end)
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
