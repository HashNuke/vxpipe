defmodule Vxpipe.CallEngine.CallLifecycleRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    Error,
    TestSelectiveAgentRuntimeModelProvider,
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

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

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

  @startup_progress [:vxpipe, :call_engine, :startup, :progress]
  @startup_stop [:vxpipe, :call_engine, :startup, :stop]

  test "monitoring a room selects its exact tenant and incarnation before caller media attaches" do
    plan = compile_plan(60_000, model: "test:blocked", wait_sounds: nil)
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_call_lifecycle_timer_scheduled, _, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room("another-tenant", plan.room_id, room.incarnation_id)

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, "another-incarnation")

    assert {:ok, monitor} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)

    :ok = TestCallLifecycleTimer.fire(readiness_timer)
    assert_receive {:DOWN, ^monitor, :process, _, {:shutdown, :startup_readiness_timeout}}, 1_000

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)
  end

  for outcome <- [:ready, :failed, :timeout, :disconnected] do
    test "observes blocked model startup through #{outcome} without private identity" do
      attach_startup_telemetry()
      model = if unquote(outcome) == :failed, do: "test:blocked-unavailable", else: "test:blocked"
      plan = compile_plan(60_000, model: model, wait_sounds: nil)
      assert {:ok, room} = start_call(plan)
      assert_receive {:test_call_lifecycle_timer_scheduled, {lifecycle, _, :max_duration}, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000

      assert_receive {:startup_diagnostic, ^lifecycle, @startup_progress, _,
                      %{blockers: [:model_inference]}},
                     1_000

      caller = Map.fetch!(plan.participants, plan.entry_caller)
      command = connection_command(plan, room, caller, "diagnostic-startup")
      assert {:ok, _} = CallEngine.TestTransferConnection.attach(command, nil)

      case unquote(outcome) do
        :timeout ->
          :ok = TestCallLifecycleTimer.fire(readiness_timer)

        :disconnected ->
          assert :ok =
                   CallEngine.TestTransferConnection.run(command, fn ->
                     CallEngine.RoomAuthority.detach_connection(
                       room_authority(plan),
                       command,
                       self()
                     )
                   end)

        _other ->
          send(preparer, :release_test_agent_runtime_model)
      end

      assert_receive {:startup_diagnostic, ^lifecycle, @startup_stop,
                      %{count: 1, duration: duration}, metadata},
                     1_000

      blockers = if unquote(outcome) == :ready, do: [], else: [:model_inference]
      assert metadata == %{outcome: unquote(outcome), blockers: blockers}
      assert duration >= 0
      refute_receive {:startup_diagnostic, ^lifecycle, @startup_stop, _, _}
    end
  end

  test "reports missing caller media after model preparation and through the startup deadline" do
    attach_startup_telemetry()
    plan = compile_plan(60_000)
    assert {:ok, _room} = start_call(plan)
    assert_receive {:test_call_lifecycle_timer_scheduled, {lifecycle, _, :max_duration}, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    assert_receive {:startup_diagnostic, ^lifecycle, @startup_progress, _, %{blockers: [:media]}},
                   1_000

    assert :ok = TestCallLifecycleTimer.fire(readiness_timer)

    assert_receive {:startup_diagnostic, ^lifecycle, @startup_stop, _,
                    %{outcome: :timeout, blockers: [:media]}}
  end

  defp attach_startup_telemetry do
    handler = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [@startup_progress, @startup_stop],
        &__MODULE__.handle_startup/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  def handle_startup(event, measurements, metadata, receiver),
    do: send(receiver, {:startup_diagnostic, self(), event, measurements, metadata})

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
                    {:shutdown, :startup_readiness_timeout}},
                   1_000

    refute room.incarnation_id == ""
  end

  for departure <- [:detach, :process_down] do
    test "cancels silent startup preparation when its caller leaves by #{departure}" do
      plan = compile_plan(60_000, model: "test:blocked", wait_sounds: nil)
      assert {:ok, room} = start_call(plan)
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000
      preparation_monitor = Process.monitor(preparer)
      authority = room_authority(plan)
      room_monitor = Process.monitor(authority)
      caller = Map.fetch!(plan.participants, plan.entry_caller)
      command = connection_command(plan, room, caller, "silent-startup")
      assert {:ok, _} = CallEngine.TestTransferConnection.attach(command, nil)

      case unquote(departure) do
        :detach ->
          assert :ok =
                   CallEngine.TestTransferConnection.run(command, fn ->
                     CallEngine.RoomAuthority.detach_connection(authority, command, self())
                   end)

        :process_down ->
          connection = CallEngine.TestTransferConnection.run(command, fn -> self() end)
          Process.exit(connection, :kill)
      end

      assert_receive {:DOWN, ^room_monitor, :process, ^authority,
                      {:shutdown, {:startup_failure, :caller_disconnected}}},
                     1_000

      assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _reason}, 1_000
      refute_receive {:test_call_ready, _}
    end
  end

  test "fails startup promptly if its wait player is killed without a playback result" do
    attach_startup_telemetry()
    plan = compile_plan(60_000, model: "test:blocked")
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000
    preparation_monitor = Process.monitor(preparer)
    authority = room_authority(plan)
    room_monitor = Process.monitor(authority)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({CallEngine.TestAudioOutputSink, observer: self()})
    command = connection_command(plan, room, caller, "failed-wait-startup")
    assert {:ok, _} = CallEngine.TestTransferConnection.attach(command, sink)
    assert_receive {:test_audio_output, ^sink, wait_frame}, 1_000
    player = wait_frame.reply_to
    Process.exit(player, :kill)

    assert_receive {:DOWN, ^room_monitor, :process, ^authority, :startup_unavailable}, 1_000
    assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 1_000
    refute_receive {:test_call_ready, _}

    assert_receive {:startup_diagnostic, _, @startup_stop, _,
                    %{outcome: :failed, blockers: blockers}}

    assert :model_inference in blockers
  end

  test "detaching a waiting caller clears queued audio and cancels preparation" do
    plan = compile_plan(60_000, model: "test:blocked")
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000
    preparation_monitor = Process.monitor(preparer)
    authority = room_authority(plan)
    room_monitor = Process.monitor(authority)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({CallEngine.TestAudioOutputSink, observer: self()})
    command = connection_command(plan, room, caller, "detached-wait-startup")
    assert {:ok, _} = CallEngine.TestTransferConnection.attach(command, sink)
    assert_receive {:test_audio_output, ^sink, wait_frame}, 1_000
    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    player_monitor = Process.monitor(wait_frame.reply_to)

    assert :ok =
             CallEngine.TestTransferConnection.run(command, fn ->
               CallEngine.RoomAuthority.detach_connection(authority, command, self())
             end)

    assert :sys.get_state(sink).callback == nil
    assert_receive {:DOWN, ^player_monitor, :process, _, _}, 1_000

    assert_receive {:DOWN, ^room_monitor, :process, ^authority,
                    {:shutdown, {:startup_failure, :caller_disconnected}}},
                   1_000

    assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 1_000
  end

  test "keeps silent startup alive when another connection still belongs to the caller" do
    plan = compile_plan(60_000, model: "test:blocked", wait_sounds: nil)
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000
    preparation_monitor = Process.monitor(preparer)
    authority = room_authority(plan)
    room_monitor = Process.monitor(authority)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    first = connection_command(plan, room, caller, "first-caller-connection")
    second = connection_command(plan, room, caller, "second-caller-connection")
    assert {:ok, _} = CallEngine.TestTransferConnection.attach(first, nil)
    assert {:ok, _} = CallEngine.TestTransferConnection.attach(second, nil)

    assert :ok =
             CallEngine.TestTransferConnection.run(first, fn ->
               CallEngine.RoomAuthority.detach_connection(authority, first, self())
             end)

    refute_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 100
    refute_receive {:DOWN, ^room_monitor, :process, ^authority, _}, 100
    send(preparer, :release_test_agent_runtime_model)
    assert_receive {:test_call_ready, _}, 1_000
    assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, :normal}, 1_000
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

    assert_receive {:DOWN, monitor, :process, _authority, {:shutdown, :maximum_duration_reached}},
                   1_000

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

    result = attach(plan, room, caller)

    assert match?({:ok, _attachment}, result) or
             match?({:error, %Error{code: :speech_to_text_unavailable}}, result)

    assert_receive :test_failing_stt_start_attempted, 1_000
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

    assert_receive {:DOWN, ^monitor, :process, ^authority,
                    {:shutdown, {:startup_failure, :speech_to_text_unavailable}}},
                   1_000

    refute_received {:test_call_ready, _room_id}
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

    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.send_text(
               send_command(plan, room, caller, "Hello")
             )

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

    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.send_text(
               send_command(plan, room, caller, "I am here")
             )

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

    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.send_text(
               send_command(plan, room, caller, "Check now")
             )

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
        %{
          speech_to_text: %{
            provider: "deepgram",
            model: "flux-general-multi",
            options: %{encoding: "opus", sample_rate: 48_000}
          }
        }
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
      schema_version: CallSpec.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      wait_sounds: Keyword.get(options, :wait_sounds, %{}),
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
          capabilities: %{
            model_inference: %{
              provider: "fixture",
              model: Keyword.get(options, :model, "test:scripted")
            }
          },
          tools: tools,
          transfers: []
        }
      },
      limits: %{max_duration_ms: max_duration_ms}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "lifecycle-call-spec", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "lifecycle-call-spec", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-lifecycle",
               actor_id: "actor-lifecycle",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      host_tools: %{"wait_for_test" => TestBlockingTool}
    }

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries)
    plan
  end

  defp attach(plan, room, caller, connection_id \\ nil) do
    command = connection_command(plan, room, caller, connection_id || unique_id("connection"))
    Vxpipe.CallEngine.TestTransferConnection.attach(command, nil)
  end

  defp connection_command(plan, room, caller, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
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
    configure_speech_to_text(
      {TestSpeechToTextTransport, [observer: self(), ready_on_start: true]}
    )
  end

  defp configure_speech_to_text({wire_module, wire_options}) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      providers: %{
        Vxpipe.Providers.Deepgram.STTSession => [
          enabled: true,
          wire_module: wire_module,
          wire_options: wire_options,
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
      Keyword.put(settings, :speech_to_text, speech_to_text)
    )
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
