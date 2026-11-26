defmodule Vxpipe.CallEngine.AgentRuntime.IdleRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, AgentTurnFailed, ToolCallCompleted}

  alias Vxpipe.CallEngine.{
    TestAudioOutputSink,
    TestTextToSpeechTransport,
    TestTransferConnection
  }

  import Vxpipe.CallEngine.TestVoiceToolRoom

  setup do
    configure()
  end

  test "native idle waits after its spoken acknowledgement and produces one typed timeout continuation" do
    {_plan, room, caller, voice, sink} = start_call()
    command = submit(room, caller, "Give me a moment", "idle-origin")
    assert_receive {:test_agent_runtime_stream, provider, request}
    assert Enum.map(request.tools, & &1.name) == ["idle"]

    {:ok, call} =
      ToolCall.new(id: "idle-operation", name: "idle", arguments: %{"duration_seconds" => 1})

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_agent_runtime_stream, acknowledgment, ack_request}

    assert Enum.any?(
             ack_request.messages,
             &(&1.role == :tool and JSON.decode!(&1.content)["status"] == "running")
           )

    reply(acknowledgment, :speaker, "Okay, I'll give you a moment.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Okay, I'll give you a moment."
    # Quiet time belongs after supported playback, rather than after tool submission.
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    settle(voice, sink, "idle-ack", command.correlation_id)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "idle-origin"}}
    settled_at = System.monotonic_time(:millisecond)
    refute_receive {:test_agent_runtime_stream, _, _}, 850
    assert_receive {:test_agent_runtime_stream, continuation, timeout_request}, 1_500
    assert System.monotonic_time(:millisecond) - settled_at >= 900
    assert timeout_request.reply_protocol == :mode_message_v1
    latest = List.last(timeout_request.messages)
    assert latest.origin == :engine

    assert JSON.decode!(latest.content) == %{
             "type" => "platform_event",
             "event" => "idle_timeout",
             "data" => %{},
             "agent_mode" => "listener"
           }

    completions =
      Enum.filter(
        timeout_request.messages,
        &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
      )

    assert [completion] = completions
    assert completion.content =~ "idle-operation"
    assert completion.content =~ ~s("status":"expired")

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "idle-operation",
                      result: %{"status" => "expired"}
                    }}

    reply(continuation, :speaker, "Are you ready now?")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Are you ready now?"
    settle(voice, sink, "idle-followup", latest_correlation(timeout_request))
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  test "silent acknowledgment waits ten seconds and emits only one timeout request" do
    {_plan, room, caller, voice, _sink} = start_call()
    submit(room, caller, "Wait ten seconds", "silent-idle")
    {acknowledgment, _request} = invoke_idle(10)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "silent-idle"}}
    settled_at = System.monotonic_time(:millisecond)
    refute_receive {:test_tts_control, ^voice, _}, 100
    refute_receive {:test_agent_runtime_stream, _, _}, 9_700
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert System.monotonic_time(:millisecond) - settled_at >= 9_800
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"

    assert Enum.count(
             request.messages,
             &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
           ) == 1

    reply(followup, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
    refute_receive {:test_tts_control, ^voice, _}, 100
  end

  test "early input waits for the genuine cancellation fact before one resumption request" do
    {plan, room, caller, voice, sink} = start_call()
    submit(room, caller, "Wait a moment", "early-idle")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "early-idle"}}

    registry =
      CallEngine.AgentActivationSupervisor.child_ref(
        plan.participants["receiver"].activation_id,
        :invocation_registry
      )

    assert {:ok, execution} =
             CallEngine.Tool.InvocationRegistry.running_execution(registry, "idle-operation")

    :ok = :sys.suspend(execution.worker)

    on_exit(fn ->
      try do
        :sys.resume(execution.worker)
      catch
        :exit, _reason -> :ok
      end
    end)

    submit(room, caller, "Ready now", "early-resumption")
    refute_receive {:test_agent_runtime_stream, _, _}, 100
    :ok = :sys.resume(execution.worker)
    assert_receive {:test_agent_runtime_stream, response, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Ready now"

    assert [completion] =
             Enum.filter(
               request.messages,
               &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
             )

    assert completion.content =~ ~s("status":"cancelled")
    reply(response, :speaker, "Let's continue.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Let's continue."
    settle(voice, sink, "early-followup", "early-resumption")
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
  end

  test "a failed acknowledgment cancels the hold without a timeout generation" do
    {_plan, room, caller, voice, _sink} = start_call()
    submit(room, caller, "Please wait", "failed-idle")
    {acknowledgment, _request} = invoke_idle(1)
    send(acknowledgment, {:test_agent_runtime_response, {:error, :provider_unavailable}})
    assert_receive {:vxpipe_event, %AgentTurnFailed{correlation_id: "failed-idle"}}

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "idle-operation",
                      result: %{"status" => "cancelled", "reason" => "acknowledgment_failed"}
                    }},
                   1_500

    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    refute_receive {:test_tts_control, ^voice, _}, 100
  end

  test "Room admission after model completion still arms the idle timeout continuation" do
    {plan, room, caller, voice, sink} = start_call()
    command = submit(room, caller, "Wait one second", "late-idle-arm")
    [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})

    coordinator =
      CallEngine.AgentActivationSupervisor.child_ref(
        plan.participants["receiver"].activation_id,
        :coordinator
      )

    :ok = :sys.suspend(room_pid)

    on_exit(fn ->
      try do
        :sys.resume(room_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {acknowledgment, _request} = invoke_idle(1)

    registry =
      CallEngine.AgentActivationSupervisor.child_ref(
        plan.participants["receiver"].activation_id,
        :invocation_registry
      )

    assert {:ok, execution} =
             CallEngine.Tool.InvocationRegistry.running_execution(registry, "idle-operation")

    task = :sys.get_state(execution.worker).task.pid
    :erlang.trace(task, true, [:send])
    {:messages, queued} = Process.info(room_pid, :messages)

    unless Enum.any?(queued, fn
             {:"$gen_call", _, {:idle, _}} -> true
             _ -> false
           end) do
      assert_receive {:trace, ^task, :send, {:"$gen_call", _, {:idle, _}}, _destination}
    end

    :erlang.trace(task, false, [:send])

    current = :sys.get_state(coordinator).current
    monitor = Process.monitor(current.task.pid)
    reply(acknowledgment, :speaker, "Okay, I will wait.")
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    state = :sys.get_state(coordinator)
    assert state.current == nil
    assert state.awaiting_output.command.id == command.id
    :ok = :sys.resume(room_pid)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Okay, I will wait."
    settle(voice, sink, "late-arm-ack", command.correlation_id)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "late-idle-arm"}}
    assert_receive {:test_agent_runtime_stream, continuation, request}, 1_500
    assert List.last(request.messages).content =~ ~s("event":"idle_timeout")
    reply(continuation, :listener, nil)
  end

  test "background results during quiet are retained without an independent model request" do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer) end)

    {_plan, room, caller, voice, _sink} =
      start_call(
        tools: %{
          "submitted_host_tool" => %{
            type: "host",
            tool: "submitted_host_tool",
            conversation_mode: "non_blocking"
          }
        },
        host_tools: %{"submitted_host_tool" => CallEngine.TestSubmittedHostTool}
      )

    submit(room, caller, "Check it while I wait", "background-idle")
    assert_receive {:test_agent_runtime_stream, provider, _request}

    {:ok, background} =
      ToolCall.new(
        id: "background-operation",
        name: "submitted_host_tool",
        arguments: %{"value" => "actual-result"}
      )

    {:ok, idle} =
      ToolCall.new(id: "idle-operation", name: "idle", arguments: %{"duration_seconds" => 1})

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [background, idle])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:submitted_host_tool_started, execution, "actual-result"}
    assert_receive {:test_agent_runtime_stream, acknowledgment, _request}
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "background-idle"}}
    send(execution, :release_submitted_host_tool)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "background-operation"}}
    refute_receive {:test_agent_runtime_stream, _, _}, 700
    refute_receive {:test_tts_control, ^voice, _}, 100
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"

    completions =
      Enum.filter(
        request.messages,
        &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
      )

    assert length(completions) == 2
    assert Enum.count(completions, &(&1.content =~ "actual-result")) == 1
    assert Enum.count(completions, &(&1.content =~ ~s("status":"expired"))) == 1
    reply(followup, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  test "losing the native idle worker retires its timer and keeps human input usable" do
    {plan, room, caller, voice, _sink} = start_call()
    submit(room, caller, "Wait a moment", "worker-idle")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "worker-idle"}}
    activation = plan.participants["receiver"].activation_id
    registry = CallEngine.AgentActivationSupervisor.child_ref(activation, :invocation_registry)

    supervisor =
      CallEngine.AgentActivationSupervisor.child_ref(activation, :invocation_supervisor)

    assert {:ok, execution} =
             CallEngine.Tool.InvocationRegistry.running_execution(registry, "idle-operation")

    monitor = Process.monitor(execution.worker)
    assert :ok = DynamicSupervisor.terminate_child(supervisor, execution.worker)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    submit(room, caller, "Continue now", "worker-resumption")
    assert_receive {:test_agent_runtime_stream, response, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Continue now"

    assert [completion] =
             Enum.filter(
               request.messages,
               &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
             )

    assert completion.content =~ ~s("status":"failed")
    reply(response, :listener, nil)
    refute_receive {:test_tts_control, ^voice, _}, 100
  end

  test "human resumption before acknowledgment generation prevents stale speech and timeout" do
    {_plan, room, caller, voice, sink} = start_call()
    submit(room, caller, "Give me a moment", "armed-idle")
    {acknowledgment, _request} = invoke_idle(1)
    monitor = Process.monitor(acknowledgment)
    submit(room, caller, "Actually continue now", "armed-resumption")
    assert_receive {:DOWN, ^monitor, :process, ^acknowledgment, _}
    assert_receive {:test_agent_runtime_stream, response, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Actually continue now"

    assert [completion] =
             Enum.filter(
               request.messages,
               &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
             )

    assert completion.content =~ ~s("status":"cancelled")
    reply(acknowledgment, :speaker, "Stale acknowledgment")
    reply(response, :speaker, "Continuing now.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Continuing now."
    settle(voice, sink, "armed-resumed", "armed-resumption")
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    refute_receive {:test_tts_control, ^voice, _}, 100
  end

  test "two idle calls from one response create only one quiet interval and timeout" do
    {_plan, room, caller, voice, _sink} = start_call()
    submit(room, caller, "Give me a moment", "duplicate-idle")
    assert_receive {:test_agent_runtime_stream, provider, _request}

    calls =
      for id <- ["idle-first", "idle-second"] do
        {:ok, call} =
          ToolCall.new(id: id, name: "idle", arguments: %{"duration_seconds" => 1})

        call
      end

    {:ok, response} = ModelResponse.new(text: "", tool_calls: calls)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_agent_runtime_stream, acknowledgment, _request}
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "duplicate-idle"}}

    assert_receive {:vxpipe_event, %CallEngine.Event.ToolCallFailed{tool_call_id: rejected}},
                   1_000

    assert rejected in ["idle-first", "idle-second"]
    refute_receive {:test_agent_runtime_stream, _, _}, 700
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"

    completions =
      Enum.filter(
        request.messages,
        &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
      )

    assert length(completions) == 2
    assert Enum.count(completions, &(&1.content =~ ~s("status":"expired"))) == 1
    assert Enum.count(completions, &(&1.content =~ ~s("status":"failed"))) == 1
    reply(followup, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    refute_receive {:test_tts_control, ^voice, _}, 100
  end

  @tag timeout: 45_000
  test "a missing acknowledgment is bounded and fresh human input remains usable" do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.update!(settings, :agent_runtime, &Keyword.put(&1, :request_timeout_ms, 60_000))
    )

    {_plan, room, caller, voice, _sink} = start_call()
    submit(room, caller, "Wait a moment", "missing-ack-idle")
    {acknowledgment, _request} = invoke_idle(1)
    monitor = Process.monitor(acknowledgment)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "idle-operation",
                      result: %{"status" => "cancelled", "reason" => "acknowledgment_timeout"}
                    }},
                   31_000

    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    refute_receive {:test_tts_control, ^voice, _}, 100
    submit(room, caller, "Continue now", "missing-ack-resumption")
    assert_receive {:DOWN, ^monitor, :process, ^acknowledgment, _}
    assert_receive {:test_agent_runtime_stream, response, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Continue now"

    assert Enum.any?(
             request.messages,
             &(&1.origin == :engine and &1.content =~ "acknowledgment_timeout")
           )

    reply(response, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  test "fresh input after expiry waits for the real completion and replaces the queued timeout" do
    {plan, room, caller, _voice, _sink} = start_call()
    submit(room, caller, "Wait", "expiry-origin")
    [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})

    # This case starts with an admitted hold and injects its deadline explicitly.
    # Admission racing silent acknowledgment is tracked separately in ~/notes/vxpipe/issues.
    :erlang.trace(room_pid, true, [:receive])
    {acknowledgment, _request} = invoke_idle(300)
    assert_receive {:trace, ^room_pid, :receive, {:"$gen_call", _, {:idle, _}}}
    :erlang.trace(room_pid, false, [:receive])
    assert %{phase: :armed} = :sys.get_state(room_pid).idle_wait
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "expiry-origin"}}

    registry =
      CallEngine.AgentActivationSupervisor.child_ref(
        plan.participants["receiver"].activation_id,
        :invocation_registry
      )

    assert {:ok, execution} =
             CallEngine.Tool.InvocationRegistry.running_execution(registry, "idle-operation")

    :ok = :sys.suspend(execution.worker)

    on_exit(fn ->
      try do
        :sys.resume(execution.worker)
      catch
        :exit, _ -> :ok
      end
    end)

    before_expiry = :sys.get_state(room_pid)
    assert before_expiry.idle_wait.phase == :quiet
    send(room_pid, {:vxpipe_idle_wait_deadline, before_expiry.idle_wait.token, :quiet})
    assert :sys.get_state(room_pid).idle_wait.phase == :expiring
    refute_receive {:test_agent_runtime_stream, _, _}, 100
    submit(room, caller, "I am ready", "expiry-resumption")
    refute_receive {:test_agent_runtime_stream, _, _}, 100
    :ok = :sys.resume(execution.worker)
    assert_receive {:test_agent_runtime_stream, model, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "I am ready"
    refute Enum.any?(request.messages, &(&1.content =~ ~s("event":"idle_timeout")))

    completions =
      Enum.filter(
        request.messages,
        &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
      )

    assert [completion] = completions
    assert completion.content =~ ~s("status":"expired")
    reply(model, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
  end

  test "caller participant departure cancels quiet even while its connection drains" do
    {_plan, room, caller, _voice, _sink} = start_call()
    submit(room, caller, "Wait", "departed-origin")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "departed-origin"}}
    [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})
    state = :sys.get_state(room_pid)
    participant = Map.fetch!(state.participant_supervisors, caller.participant_id)
    monitor = Process.monitor(participant)

    assert :ok =
             CallEngine.RoomParticipantSupervisor.stop_participant(
               room.incarnation_id,
               participant
             )

    assert_receive {:DOWN, ^monitor, :process, ^participant, _reason}
    assert_receive {:vxpipe_connection_unavailable, :participant_unavailable}
    state = :sys.get_state(room_pid)
    refute MapSet.member?(state.participant_ids, caller.participant_id)
    assert Map.has_key?(state.connections, "idle-human")
    refute_receive {:test_agent_runtime_stream, _, _}, 1_500
    assert :sys.get_state(room_pid).idle_wait == nil
  end

  test "stop and wait interrupts an almost-finished answer before acknowledging and waiting" do
    {_plan, room, caller, voice, sink} = start_call()
    submit(room, caller, "Explain it", "nearly-finished")
    assert_receive {:test_agent_runtime_stream, original, _request}
    reply(original, :speaker, "This is the original answer.")
    assert_receive {:test_tts_control, ^voice, _speak}
    assert_receive {:test_tts_control, ^voice, _flush}

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechStarted","speech_id":"almost-done"})
    )

    TestTextToSpeechTransport.deliver_audio(voice, :binary.copy(<<1, 0>>, 48_000))
    assert_receive {:test_audio_output, ^sink, old_frame}
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_progress(sink, 990, 1_000)

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentSpeechProgressed{played_ms: 990, total_ms: 1_000}}

    command = submit(room, caller, "Stop and give me a moment", "almost-done-idle")
    assert_receive {:test_audio_output_interrupt, ^sink, "nearly-finished", 990}
    assert_receive {:test_tts_control, ^voice, interrupt}
    assert JSON.decode!(interrupt)["type"] == "Interrupt"

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnInterrupted{
                      correlation_id: "nearly-finished",
                      played_ms: 990
                    }}

    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :speaker, "Okay, I will wait.")
    refute_receive {:test_tts_control, ^voice, _}, 100

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechInterrupted","audio_played_ms":990,"text_spoken":"This is the original","text_remaining":"answer.","metadata":{"speech_id":"almost-done"}})
    )

    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Okay, I will wait."

    send(
      old_frame.reply_to,
      {:vxpipe_audio_playback, sink, "nearly-finished", {:completed, 1_000}}
    )

    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    settle(voice, sink, "almost-done-ack", command.correlation_id)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "almost-done-idle"}}
    refute_receive {:test_agent_runtime_stream, _, _}, 850
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"
    reply(followup, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  for outcome <- [:failed, :stalled] do
    @tag timeout: 45_000
    test "#{outcome} acknowledgment playback cannot leave an unbounded idle hold" do
      {_plan, room, caller, voice, sink} = start_call()
      submit(room, caller, "Wait a moment", "sink-idle")
      {acknowledgment, _request} = invoke_idle(1)
      :ok = TestAudioOutputSink.defer_finish(sink, true)
      reply(acknowledgment, :speaker, "Okay, I will wait.")
      assert_receive {:test_tts_control, ^voice, _speak}
      assert_receive {:test_tts_control, ^voice, _flush}

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"SpeechStarted","speech_id":"sink-ack"})
      )

      TestTextToSpeechTransport.deliver_audio(voice, <<1, 0, 2, 0>>)
      assert_receive {:test_audio_output, ^sink, _frame}

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"SpeechMetadata","speech_id":"sink-ack"})
      )

      assert_receive {:test_audio_output_finish, ^sink, "sink-idle"}

      if unquote(outcome) == :failed do
        :ok = TestAudioOutputSink.complete_finish(sink, {:error, :unavailable})
        assert_receive {:vxpipe_connection_unavailable, :agent_unavailable}, 1_000
      end

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{
                        tool_call_id: "idle-operation",
                        result: %{"status" => "cancelled", "reason" => "acknowledgment_timeout"}
                      }},
                     31_000

      refute_receive {:test_agent_runtime_stream, _, _}, 1_100
      [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})
      assert :sys.get_state(room_pid).idle_wait == nil
    end
  end

  test "ordinary idle is suspended through an explicit wait and rebased after its response" do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.update!(settings, :call_lifecycle, &Keyword.put(&1, :idle_timeout_ms, 500))
    )

    {_plan, room, caller, _voice, _sink} = start_call()
    submit(room, caller, "Wait", "ordinary-idle-origin")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "ordinary-idle-origin"}}
    refute_receive {:test_agent_runtime_stream, _, _}, 850
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"
    refute_receive {:test_agent_runtime_stream, _, _}, 600
    reply(followup, :listener, nil)
    correlation = latest_correlation(request)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^correlation}}
    refute_receive {:test_agent_runtime_stream, _, _}, 400
    assert_receive {:test_agent_runtime_stream, ordinary, ordinary_request}, 500
    assert JSON.decode!(List.last(ordinary_request.messages).content)["event"] == "idle_timeout"
    refute latest_correlation(ordinary_request) == correlation
    reply(ordinary, :listener, nil)
  end

  test "connection replacement retires its old idle timer and accepts fresh input" do
    {_plan, room, caller, _voice, sink} = start_call()
    submit(room, caller, "Wait", "connection-idle")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "connection-idle"}}
    [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})
    state = :sys.get_state(room_pid)
    token = state.idle_wait.token
    old_connection = state.connections["idle-human"].pid

    {:ok, attach} =
      AttachConnection.new(
        tenant_id: room.tenant_id,
        actor_id: "actor-demo",
        room_id: room.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "idle-human",
        deadline: deadline()
      )

    assert :ok =
             TestTransferConnection.run(attach, fn ->
               CallEngine.RoomAuthority.detach_connection(room_pid, attach, self())
             end)

    assert :sys.get_state(room_pid).idle_wait == nil
    monitor = Process.monitor(old_connection)
    assert :ok = stop_supervised({TestTransferConnection, "idle-human"})
    assert_receive {:DOWN, ^monitor, :process, ^old_connection, _}
    assert {:ok, _} = TestTransferConnection.attach(attach, sink)
    refute :sys.get_state(room_pid).connections["idle-human"].pid == old_connection
    send(room_pid, {:vxpipe_idle_wait_deadline, token, :quiet})
    refute_receive {:test_agent_runtime_stream, _, _}, 1_100
    submit(room, caller, "Continue on the new connection", "replacement-input")
    assert_receive {:test_agent_runtime_stream, model, request}

    assert JSON.decode!(List.last(request.messages).content)["message"] ==
             "Continue on the new connection"

    assert Enum.any?(
             request.messages,
             &(&1.origin == :engine and &1.content =~ ~s("status":"cancelled"))
           )

    reply(model, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  test "a fresh idle operation ignores the retired wait's deadline" do
    {_plan, room, caller, _voice, _sink} = start_call()
    submit(room, caller, "Wait", "first-idle")
    {acknowledgment, _request} = invoke_idle(1)
    reply(acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first-idle"}}
    [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})
    retired_token = :sys.get_state(room_pid).idle_wait.token
    submit(room, caller, "Wait one more second", "second-idle")
    assert_receive {:test_agent_runtime_stream, model, _request}

    {:ok, call} =
      ToolCall.new(
        id: "second-idle-operation",
        name: "idle",
        arguments: %{"duration_seconds" => 1}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(model, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_agent_runtime_stream, second_acknowledgment, _request}
    reply(second_acknowledgment, :listener, nil)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "second-idle"}}
    refute :sys.get_state(room_pid).idle_wait.token == retired_token
    send(room_pid, {:vxpipe_idle_wait_deadline, retired_token, :quiet})
    refute_receive {:test_agent_runtime_stream, _, _}, 850
    assert_receive {:test_agent_runtime_stream, followup, request}, 1_000
    assert JSON.decode!(List.last(request.messages).content)["event"] == "idle_timeout"

    completions =
      Enum.filter(
        request.messages,
        &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
      )

    assert length(completions) == 2
    assert Enum.count(completions, &(&1.content =~ ~s("status":"cancelled"))) == 1
    assert Enum.count(completions, &(&1.content =~ ~s("status":"expired"))) == 1
    reply(followup, :listener, nil)
    refute_receive {:test_agent_runtime_stream, _, _}, 100
  end

  defp invoke_idle(seconds) do
    assert_receive {:test_agent_runtime_stream, provider, _request}

    {:ok, call} =
      ToolCall.new(
        id: "idle-operation",
        name: "idle",
        arguments: %{"duration_seconds" => seconds}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_agent_runtime_stream, acknowledgment, request}
    {acknowledgment, request}
  end

  defp latest_correlation(request), do: request.correlation.tool_context.correlation_id
  defp deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
