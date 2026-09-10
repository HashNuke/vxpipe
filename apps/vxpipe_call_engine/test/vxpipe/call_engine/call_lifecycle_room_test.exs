defmodule Vxpipe.CallEngine.CallLifecycleRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    Error,
    TestAgentRuntimeModelProvider,
    TestBlockingTool,
    TestCallLifecycleTimer,
    TestFailingSpeechToTextTransport,
    TestSpeechToTextTransport
  }

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Provider.Deepgram.Flux

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
      Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer)
    end)

    :ok
  end

  test "fails an unready call when its startup deadline expires" do
    plan = compile_plan(60_000)
    assert {:ok, room} = start_call(plan)
    authority = room_authority(plan)
    monitor = Process.monitor(authority)

    assert_receive {:test_call_lifecycle_timer_scheduled, {_lifecycle, _token, :max_duration},
                    60_000}

    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
    assert {_lifecycle, _token, :readiness} = readiness_timer

    :ok = TestCallLifecycleTimer.fire(readiness_timer)

    assert_receive {:DOWN, ^monitor, :process, ^authority,
                    {:shutdown, :startup_readiness_timeout}}

    refute room.incarnation_id == ""
  end

  test "ends a ready call at its pinned maximum duration" do
    plan = compile_plan(1_000)
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 1_000}
    assert {_lifecycle, _token, :max_duration} = maximum_timer
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, attachment} = attach(plan, room, caller)
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)

    assert_receive {:DOWN, monitor, :process, _authority, {:shutdown, :maximum_duration_reached}}
    assert monitor == attachment.room_monitor
  end

  test "ends startup immediately when the selected speech provider cannot start" do
    configure_failing_speech_to_text()
    plan = compile_plan(60_000, speech_to_text?: true)
    assert {:ok, room} = start_call(plan)
    authority = room_authority(plan)
    monitor = Process.monitor(authority)

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:error, %Error{code: :speech_to_text_unavailable}} =
             attach(plan, room, caller)

    assert_receive :test_failing_stt_start_attempted
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

    assert_receive {:DOWN, ^monitor, :process, ^authority,
                    {:shutdown, {:startup_failure, :speech_to_text_unavailable}}}
  end

  test "notifies a waiting agent once and rearms only after new caller activity" do
    plan = compile_plan(60_000)
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
    refute_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, _attachment} = attach(plan, room, caller, "connection-lifecycle")
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_call_lifecycle_timer_scheduled, first_idle_timer, 15_000}

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "Hello"))
    assert_receive {:test_call_lifecycle_timer_cancelled, ^first_idle_timer}
    assert_receive {:test_agent_runtime_stream, first_provider, _first_request}
    reply(first_provider, "Hello back.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    assert_receive {:test_call_lifecycle_timer_scheduled, second_idle_timer, 15_000}

    :ok = TestCallLifecycleTimer.fire(first_idle_timer)
    refute_receive {:test_agent_runtime_stream, _stale_provider, _stale_request}

    :ok = TestCallLifecycleTimer.fire(second_idle_timer)
    assert_receive {:test_agent_runtime_stream, idle_provider, idle_request}
    idle_prompt = List.last(idle_request.messages)
    assert idle_prompt.origin == :engine
    assert idle_prompt.content =~ "caller has provided no new input"

    reply(idle_provider, "Are you still there?")
    assert_receive {:vxpipe_event, %TextOutput{text: "Are you still there?"}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    refute_receive {:test_call_lifecycle_timer_scheduled, _repeated_idle_timer, 15_000}

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "I am here"))
    assert_receive {:test_agent_runtime_stream, second_provider, _second_request}
    reply(second_provider, "Great.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    assert_receive {:test_call_lifecycle_timer_scheduled, _third_idle_timer, 15_000}
  end

  test "starts caller-idle timing only after a generated greeting completes" do
    plan = compile_plan(60_000, first_message: %{mode: "generated"})
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, _attachment} = attach(plan, room, caller, "connection-lifecycle")
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).origin == :engine
    refute_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}

    reply(provider, "Welcome.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    assert_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}
  end

  test "does not count a handed-off tool wait as caller idle" do
    plan = compile_plan(60_000, tool?: true)
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, _attachment} = attach(plan, room, caller, "connection-lifecycle")
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_call_lifecycle_timer_scheduled, first_idle_timer, 15_000}

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "Check now"))
    assert_receive {:test_call_lifecycle_timer_cancelled, ^first_idle_timer}
    assert_receive {:test_agent_runtime_stream, provider, _request}
    reply_with_tool(provider, "idle-tool-call")

    assert_receive {:test_blocking_tool_started, execution}
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "idle-tool-call"}}
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _request}
    reply(acknowledgement_provider, "I am checking.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    refute_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}

    send(execution, :release_test_tool)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "idle-tool-call"}}
    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    refute_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}

    reply(completion_provider, "The check completed.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    assert_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}
  end

  test "caller speech cancels an armed idle timer before transcription completes" do
    configure_working_speech_to_text()
    plan = compile_plan(60_000, speech_to_text?: true)
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, _attachment} = attach(plan, room, caller, "connection-lifecycle")
    assert_receive {:test_stt_transport_started, transport, _connection}
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_call_lifecycle_timer_scheduled, idle_timer, 15_000}

    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, ""))
    assert_receive {:test_call_lifecycle_timer_cancelled, ^idle_timer}
  end

  defp start_call(plan) do
    CallEngine.start_call(plan,
      call_lifecycle: [
        readiness_timeout_ms: 30_000,
        idle_timeout_ms: 15_000,
        timer: {TestCallLifecycleTimer, [observer: self()]}
      ]
    )
  end

  defp compile_plan(max_duration_ms, options \\ []) do
    caller_capabilities =
      if Keyword.get(options, :speech_to_text?, false) do
        %{speech_to_text: "test-stt"}
      else
        %{}
      end

    tools =
      if Keyword.get(options, :tool?, false) do
        %{"wait_for_test" => %{type: "host", tool: "wait_for_test"}}
      else
        %{}
      end

    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: caller_capabilities
        },
        "receiver" => %{
          type: "agent",
          prompt: "Wait for the caller.",
          first_message: Keyword.get(options, :first_message, %{mode: "wait_for_input"}),
          capabilities: %{model_inference: "test-model"},
          tools: tools,
          transfers: []
        }
      },
      limits: %{max_duration_ms: max_duration_ms}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "lifecycle-definition", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "lifecycle-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-lifecycle",
               actor_id: "actor-lifecycle",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        },
        "test-stt" => %{
          kind: :speech_to_text,
          provider: Flux,
          options: %{model: "flux-general-multi", encoding: :opus, sample_rate: 48_000}
        }
      },
      host_tools: %{"wait_for_test" => TestBlockingTool}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp attach(plan, room, caller, connection_id \\ nil) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id || unique_id("connection"),
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    CallEngine.attach_connection(command)
  end

  defp send_command(plan, room, caller, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "connection-lifecycle",
               correlation_id: unique_id("turn"),
               content: content,
               audio_response: false,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp reply(provider, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp reply_with_tool(provider, id) do
    assert {:ok, call} = ToolCall.new(id: id, name: "wait_for_test", arguments: %{})
    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp turn_message(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "request-lifecycle-idle",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end

  defp room_authority(plan) do
    [{authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    authority
  end

  defp configure_failing_speech_to_text do
    configure_speech_to_text({TestFailingSpeechToTextTransport, [observer: self()]})
  end

  defp configure_working_speech_to_text do
    configure_speech_to_text({TestSpeechToTextTransport, [observer: self()]})
  end

  defp configure_speech_to_text(transport) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [
        api_key: "test-runtime-secret",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      ],
      transport: transport,
      media_ingress: [
        maximum_frames: 8,
        maximum_bytes: 1_024,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 2
      ]
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :speech_to_text, speech_to_text)
    )
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
