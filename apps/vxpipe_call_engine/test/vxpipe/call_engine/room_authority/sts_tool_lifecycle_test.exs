defmodule Vxpipe.CallEngine.RoomAuthority.STSToolLifecycleTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Tool.InvocationRegistry
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.{STSSession, DuplexSTSSession}

  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup context do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_speech,
        providers: %{STSSession => [enabled: true], DuplexSTSSession => [enabled: true]}
      )
      |> Keyword.update!(:agent_runtime, &Keyword.merge(&1, Map.get(context, :tool_limits, [])))

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    room(context)
  end

  for model <- ["morse", "morse-duplex"] do
    @tag :conversation_admission
    @tag native_model: model
    test "#{model} blocking tool holds later input until its result is consumed", context do
      {worker, started} = submit(context)

      assert {:error, :held} =
               SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")

      refute_received {:vxpipe_event, %ToolCallStarted{name: "current_time"}}
      send(worker, :finish)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: id}}, 1_000
      assert id == started.tool_call_id
      _ = :sys.get_state(context.authority)
      refute_received {:vxpipe_event, %ToolCallStarted{name: "current_time"}}
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
    end

    @tag :conversation_admission
    @tag native_model: model, conversation_mode: "non_blocking"
    test "#{model} nonblocking tool permits unrelated input while retaining pending work",
         context do
      {worker, started} = submit(context)
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
      _ = :sys.get_state(context.authority)

      assert {:ok, [pending]} =
               InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))

      assert pending.invocation_id == started.tool_call_id
      assert pending.conversation_mode == :non_blocking
      assert pending.status == :running
      send(worker, :finish)

      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle", tool_call_id: id}},
                     1_000

      assert id == started.tool_call_id
      _ = :sys.get_state(context.authority)
      assert leases(context) == []
    end

    @tag :conversation_admission
    @tag native_model: model
    test "#{model} nonblocking completion cannot release another tool's blocking hold", context do
      {background, background_started} = submit(context, "background")
      {blocking, blocking_started} = submit(context)
      send(background, :finish)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: background_id}}, 1_000
      assert background_id == background_started.tool_call_id

      assert {:error, :held} =
               SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")

      send(blocking, :finish)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: blocking_id}}, 1_000
      assert blocking_id == blocking_started.tool_call_id
      _ = :sys.get_state(context.authority)
      refute_received {:vxpipe_event, %ToolCallStarted{name: "current_time"}}
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
    end
  end

  @tag :conversation_admission
  test "blocking input stays held between local result acceptance and registry consumption",
       context do
    {worker, _started} = submit(context)
    capability = context.capability
    authority = context.authority
    registry = Tree.invocation_registry(capability)
    :erlang.trace(authority, true, [:send])
    :ok = :sys.suspend(capability)

    try do
      send(worker, :finish)

      assert_receive {:trace, ^authority, :send, {:"$gen_call", _, {:send_tool_result, _, _}},
                      ^capability},
                     1_000

      :ok = :sys.suspend(registry)

      try do
        :ok = :sys.resume(capability)
        assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle"}}, 1_000
        assert {:error, :held} = SpeechToSpeech.push_text(capability, "TOOL current_time {}")
      after
        :sys.resume(registry)
      end
    after
      :sys.resume(capability)
    end

    _ = :sys.get_state(authority)
    assert :ok = SpeechToSpeech.push_text(capability, "TOOL current_time {}")
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
  end

  @tag :conversation_admission
  test "forwarded requests provisionally hold input until room admission resolves", context do
    capability = context.capability
    authority = context.authority
    :erlang.trace(capability, true, [:send])
    :ok = :sys.suspend(authority)

    try do
      assert :ok = SpeechToSpeech.push_text(capability, "TOOL lifecycle {}")

      assert_receive {:trace, ^capability, :send, {:vxpipe_sts_tool_event, ^capability, _, _},
                      ^authority},
                     1_000

      assert {:error, :held} = SpeechToSpeech.push_text(capability, "TOOL current_time {}")
      refute_received {:host_started, _, _}
    after
      :sys.resume(authority)
    end

    assert_receive {:host_started, worker, _}, 1_000
    send(worker, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle"}}, 1_000
  end

  @tag :conversation_admission
  test "stale forwarded scope fails explicitly without orphaning a provisional hold", context do
    capability = context.capability
    authority = context.authority
    monitor = Process.monitor(authority)
    :erlang.trace(capability, true, [:send])
    :ok = :sys.suspend(authority)

    try do
      assert :ok = SpeechToSpeech.push_text(capability, "TOOL lifecycle {}")

      assert_receive {:trace, ^capability, :send, {:vxpipe_sts_tool_event, ^capability, _, _},
                      ^authority},
                     1_000

      :sys.replace_state(authority, fn state ->
        put_in(state.speech_to_speech_capability.input_epoch, make_ref())
      end)
    after
      :sys.resume(authority)
    end

    assert_receive {:DOWN, ^monitor, :process, ^authority, :tool_admission_unavailable}, 1_000
    refute_received {:host_started, _, _}
  end

  @tag :admission_review
  test "an undeliverable rejection cannot strand a provisional blocker", context do
    capability = context.capability
    authority = context.authority
    monitor = Process.monitor(authority)
    provider = CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    :erlang.trace(capability, true, [:send])
    :ok = :sys.suspend(authority)

    try do
      assert :ok = SpeechToSpeech.push_text(capability, "TOOL unselected {}")

      assert_receive {:trace, ^capability, :send,
                      {:vxpipe_sts_tool_event, ^capability, _,
                       %{event: %{kind: :tool_call, turn_ref: turn}}}, ^authority},
                     1_000

      assert :ok = STSSession.interrupt(provider, turn)

      assert_receive {:trace, ^capability, :send,
                      {:vxpipe_sts_tool_event, ^capability, _,
                       %{event: %{kind: :tool_cancelled}}}, ^authority},
                     1_000
    after
      :sys.resume(authority)
    end

    assert_receive {:DOWN, ^monitor, :process, ^authority, :tool_result_unavailable}, 1_000
    refute_received {:host_started, _, _}
  end

  @tag :shared_dispatch
  test "a native platform alias completes through the owned invocation worker", context do
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")
    assert_receive {:vxpipe_event, %ToolCallStarted{name: "current_time"} = started}, 1_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "current_time", result: %{"timezone" => "UTC"}} =
                      completed},
                   1_000

    assert completed.tool_call_id == started.tool_call_id
    assert completed.correlation_id == started.correlation_id
    assert :sys.get_state(context.authority).sts_tool_calls == %{}
  end

  @tag :shared_dispatch
  test "native host arguments are rejected before invocation or public started events", context do
    assert :ok = SpeechToSpeech.push_text(context.capability, ~s(TOOL lifecycle {"extra":true}))

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{name: "lifecycle", reason: :invalid_arguments}},
                   1_000

    refute_received {:host_started, _, _}
    refute_received {:vxpipe_event, %ToolCallStarted{}}
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
    assert :sys.get_state(context.authority).sts_tool_calls == %{}
  end

  @tag :shared_settlement
  test "completed native tools release capacity for more than sixteen sequential requests",
       context do
    for _ <- 1..20 do
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL current_time {}")
      assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: id}}, 1_000
      assert_receive {:vxpipe_event, %{tool_call_id: ^id} = terminal}, 1_000
      assert %ToolCallCompleted{name: "current_time"} = terminal
      _ = :sys.get_state(context.authority)
    end

    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
    assert leases(context) == []
  end

  @tag :interruption_delivery
  test "unrelated speech activity does not strand an admitted tool completion", context do
    {worker, started} = submit(context)

    :sys.replace_state(context.authority, fn state ->
      put_in(state.speech_to_speech_capability.activity_turn, %{turn_ref: make_ref()})
    end)

    send(worker, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: id}}, 1_000
    assert id == started.tool_call_id
    assert :sys.get_state(context.authority).sts_tool_calls == %{}
    assert leases(context) == []
  end

  @tag :shared_settlement
  @tag :settlement_review
  test "a rejected native result terminates explicitly instead of publishing successful delivery",
       context do
    {worker, _started} = submit(context)
    provider = CallEngine.Speech.Session.provider(:sys.get_state(context.capability).session)

    # Fault injection: the provider loses its association after engine admission.
    :sys.replace_state(provider, &%{&1 | pending_tools: %{}})

    :sys.replace_state(context.authority, fn state ->
      %{state | sts_caller_turns: %{make_ref() => %{last_text: "synthetic-private-caller-text"}}}
    end)

    original = Application.get_env(:logger, :translator_inspect_opts, [])
    Application.put_env(:logger, :translator_inspect_opts, limit: :infinity)
    on_exit(fn -> Application.put_env(:logger, :translator_inspect_opts, original) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        monitor = Process.monitor(context.authority)
        send(worker, :finish)
        authority = context.authority
        assert_receive {:DOWN, ^monitor, :process, ^authority, :tool_result_unavailable}, 1_000
        refute_received {:vxpipe_event, %ToolCallCompleted{}}
      end)

    refute log =~ "synthetic-private-caller-text"
  end

  @tag :shared_dispatch
  test "a native platform hangup publishes its result and ends the authorized room", context do
    authority = context.authority
    monitor = Process.monitor(authority)
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL end_call {}")
    assert_receive {:vxpipe_event, %ToolCallStarted{name: "end_call"}}, 1_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "end_call", result: %{"status" => "ending"}}},
                   1_000

    assert_receive {:DOWN, ^monitor, :process, ^authority, _reason}, 1_000
  end

  @tag variables: ["read", "write"]
  @tag :shared_variables
  test "native tools read and update only the participant's permitted variables", context do
    assert :ok =
             SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL read_variables {"sections":["intake"]})
             )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "read_variables", result: %{"sections" => sections}}},
                   1_000

    assert sections == %{"intake" => %{"revision" => 0, "value" => %{"note" => "known"}}}
    _ = :sys.get_state(context.authority)

    update = %{
      "section_name" => "intake",
      "variable_name" => "note",
      "value" => "updated",
      "expected_revision" => 0
    }

    assert :ok =
             SpeechToSpeech.push_text(
               context.capability,
               "TOOL update_variable " <> JSON.encode!(update)
             )

    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "update_variable"}}, 1_000
    _ = :sys.get_state(context.authority)

    assert :ok =
             SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL read_variables {"sections":["intake"]})
             )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "read_variables", result: %{"sections" => updated}}},
                   1_000

    assert updated == %{"intake" => %{"revision" => 1, "value" => %{"note" => "updated"}}}
    _ = :sys.get_state(context.authority)

    assert :ok =
             SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL read_variables {"sections":["private"]})
             )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "read_variables", result: %{"error" => _}}},
                   1_000
  end

  @tag variables: ["read"]
  @tag :shared_variables
  test "native read-only participants cannot invoke the unselected variable update tool",
       context do
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL update_variable {}")

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{name: "update_variable", reason: :unauthorized}},
                   1_000

    refute_received {:vxpipe_event, %ToolCallStarted{}}
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
    assert :sys.get_state(context.authority).sts_tool_calls == %{}
  end

  test "actual room host work is invocation-owned and accepted results release their lease",
       context do
    {worker, started} = submit(context)
    bridge = Tree.tool_completions(context.capability)
    :erlang.trace(bridge, true, [:send])
    registry = Tree.invocation_registry(context.capability)
    supervisor = Tree.invocation_supervisor(context.capability)
    assert [{_, invocation, :worker, _}] = DynamicSupervisor.which_children(supervisor)
    assert {:links, links} = Process.info(worker, :links)
    assert invocation in links
    assert {:ok, [status]} = InvocationRegistry.snapshot(registry)
    assert status.invocation_id == started.tool_call_id
    assert status.status == :running
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}, 1_000
    assert completed.tool_call_id == started.tool_call_id
    assert completed.correlation_id == started.correlation_id
    assert completed.result == %{"retained" => true}
    _ = :sys.get_state(context.authority)
    assert {:ok, []} = InvocationRegistry.snapshot(registry)
    assert leases(context) == []

    assert_receive {:trace, ^bridge, :send, {:vxpipe_sts_tool_completion, ^bridge, lease}, _},
                   1_000

    send(context.authority, {:vxpipe_sts_tool_completion, bridge, lease})
    _ = :sys.get_state(context.authority)
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
    assert {:ok, []} = InvocationRegistry.snapshot(registry)
  end

  for event <- [:vxpipe_sts_tool_executed, :vxpipe_sts_tool_timeout] do
    @tag :obsolete_tool_events
    test "obsolete #{event} messages cannot settle owned invocations", context do
      {worker, started} = submit(context)
      [{call, _pending}] = Map.to_list(:sys.get_state(context.authority).sts_tool_calls)
      send(context.authority, obsolete_message(unquote(event), context.capability, call))
      state = :sys.get_state(context.authority)
      assert Map.has_key?(state.sts_tool_calls, call)
      refute_received {:vxpipe_event, %ToolCallCompleted{}}
      refute_received {:vxpipe_event, %ToolCallFailed{}}
      send(worker, :finish)

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: id, result: %{"retained" => true}}},
                     1_000

      assert id == started.tool_call_id
    end
  end

  defp obsolete_message(:vxpipe_sts_tool_executed, capability, call),
    do: {:vxpipe_sts_tool_executed, capability, call, {:ok, %{"forged" => true}}}

  defp obsolete_message(:vxpipe_sts_tool_timeout, capability, call),
    do: {:vxpipe_sts_tool_timeout, capability, call}

  @tag :interruption_delivery
  test "speech interruption preserves accepted work and delivers its final result", context do
    {worker, started} = submit(context)
    assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
    send(worker, :probe)
    assert_receive {:host_running, ^worker}
    send(worker, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: id}}, 1_000
    assert id == started.tool_call_id
    assert :sys.get_state(context.authority).sts_tool_calls == %{}
    assert :sys.get_state(context.capability).tool_calls == %{}
    assert leases(context) == []
    refute_received {:vxpipe_event, %ToolCallCancelled{}}
    refute_received {:host_started, _, _}
  end

  @tag :provider_cancellation
  test "provider cancellation preserves accepted work and fails explicitly if result delivery is lost",
       context do
    {worker, _started} = submit(context)
    capability = context.capability
    authority = context.authority
    monitor = Process.monitor(authority)
    [{_call, pending}] = Map.to_list(:sys.get_state(capability).tool_calls)
    provider = CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    :erlang.trace(capability, true, [:send])
    assert :ok = STSSession.interrupt(provider, pending.turn_ref)

    assert_receive {:trace, ^capability, :send,
                    {:vxpipe_sts_tool_event, ^capability, _, %{event: %{kind: :tool_cancelled}}},
                    ^authority},
                   1_000

    send(worker, :probe)
    assert_receive {:host_running, ^worker}
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^authority, :tool_result_unavailable}, 1_000
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
    refute_received {:host_started, _, _}
  end

  @tag :cancellation_review
  test "provider cancellation reconciles an outcome already retained by the completion bridge",
       context do
    {worker, started} = submit(context)
    capability = context.capability
    authority = context.authority
    bridge = Tree.tool_completions(capability)
    :erlang.trace(bridge, true, [:send])
    monitor = Process.monitor(authority)
    [{_call, pending}] = Map.to_list(:sys.get_state(capability).tool_calls)
    provider = CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    state = :sys.get_state(authority)
    policy = state.media_policy_authority
    caller = state.speech_to_speech_capability.input_handle.identity.participant_id

    # Remove policy presence without replacing the allocation, retaining the
    # terminal outcome until cancellation arrives after its lease notification.
    assert {:ok, _snapshot} = CallEngine.MediaPolicy.Authority.leave(policy, caller)

    send(worker, :finish)
    assert_receive {:trace, ^bridge, :send, {:vxpipe_sts_tool_completion, ^bridge, _}, _}, 1_000
    assert map_size(:sys.get_state(authority).sts_tool_calls) == 1
    assert [lease] = leases(context)
    assert lease.invocation_id == started.tool_call_id

    assert :ok = STSSession.interrupt(provider, pending.turn_ref)
    assert_receive {:DOWN, ^monitor, :process, ^authority, :tool_result_unavailable}, 1_000
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
    refute_received {:host_started, _, _}
  end

  @tag :shared_bounds
  @tag tool_limits: [tool_invocation_timeout_ms: 100]
  test "configured execution deadline kills the host worker and settles UNKNOWN", context do
    {worker, _} = submit(context)
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1_000
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unknown}}, 1_000
    _ = :sys.get_state(context.authority)
    assert leases(context) == []
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
    refute_received {:host_started, _, _}
  end

  @tag :shared_bounds
  @tag conversation_mode: "non_blocking", tool_limits: [maximum_tool_invocations: 2]
  test "native admission respects configured worker capacity and recovers after consumption",
       context do
    {first, _} = submit(context)
    {second, _} = submit(context)
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: rejected}}, 1_000

    assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: ^rejected, reason: :saturated}},
                   1_000

    _ = :sys.get_state(context.authority)
    refute_received {:host_started, _, _}
    send(first, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle"}}, 1_000
    _ = :sys.get_state(context.authority)
    {third, _} = submit(context)
    send(second, :finish)
    send(third, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle"}}, 1_000
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "lifecycle"}}, 1_000
    _ = :sys.get_state(context.authority)
  end

  @tag :shared_bounds
  @tag tool_limits: [maximum_tool_result_bytes: 128]
  test "native outcomes use the configured common result limit", context do
    {worker, _} = submit(context)
    send(worker, {:finish, %{"payload" => String.duplicate("x", 256)}})
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :invalid_result}}, 1_000
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
    _ = :sys.get_state(context.authority)
    assert leases(context) == []
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
  end

  for loss <- [:capability, :activation, :room_owner, :registry, :supervisor, :bridge] do
    test "#{loss} loss ends actual submitted host work", context do
      {worker, _} = submit(context)
      monitor = Process.monitor(worker)

      case unquote(loss) do
        :capability ->
          Process.exit(context.capability, :kill)

        :activation ->
          assert :ok =
                   RoomCapabilitySupervisor.stop_capability(
                     context.room.incarnation_id,
                     context.capability
                   )

        :room_owner ->
          Process.exit(context.authority, :kill)

        :registry ->
          Process.exit(Tree.invocation_registry(context.capability), :kill)

        :supervisor ->
          Process.exit(Tree.invocation_supervisor(context.capability), :kill)

        :bridge ->
          Process.exit(Tree.tool_completions(context.capability), :kill)
      end

      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    end
  end

  @tag conversation_mode: "non_blocking", tool_limits: [maximum_tool_invocations: 16]
  test "interruption preserves concurrent workers and each completion frees its own capacity",
       context do
    pending =
      for _ <- 1..16 do
        {worker, started} = submit(context)
        assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
        {worker, started.tool_call_id}
      end

    assert DynamicSupervisor.count_children(Tree.invocation_supervisor(context.capability)).active ==
             16

    for {worker, id} <- pending do
      send(worker, :finish)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 1_000
      _ = :sys.get_state(context.authority)
    end

    assert leases(context) == []
    {worker, started} = submit(context)
    send(worker, :finish)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: id}}, 1_000
    assert id == started.tool_call_id
    refute_received {:vxpipe_event, %ToolCallCancelled{}}
  end

  test "more than sixteen interrupted tools deliver and release their completion leases",
       context do
    for _ <- 1..20 do
      {worker, started} = submit(context)
      assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
      send(worker, :finish)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: id}}, 1_000
      assert id == started.tool_call_id
      _ = :sys.get_state(context.authority)
    end

    assert leases(context) == []
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
    refute_received {:vxpipe_event, %ToolCallCancelled{}}
  end

  defp leases(context) do
    GenServer.call(Tree.tool_completions(context.capability), :leases)
  end

  test "expired room admission cannot execute after a blocked supervisor resumes", context do
    registry = Tree.invocation_registry(context.capability)
    supervisor = Tree.invocation_supervisor(context.capability)
    :erlang.trace(registry, true, [:send])
    :ok = :sys.suspend(supervisor)

    try do
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")

      assert_receive {:trace, ^registry, :send, {:"$gen_call", _, {:start_child, _}},
                      ^supervisor},
                     1_000

      assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unavailable}}, 3_000
    after
      :sys.resume(supervisor)
      :erlang.trace(registry, false, [:send])
    end

    assert {:ok, []} = InvocationRegistry.snapshot(registry)
    assert DynamicSupervisor.which_children(supervisor) == []
    refute_receive {:host_started, _, _}
  end

  defp submit(context, name \\ "lifecycle") do
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL " <> name <> " {}")
    assert_receive {:vxpipe_event, %ToolCallStarted{name: ^name} = started}, 1_000
    assert_receive {:host_started, worker, tool_context}, 1_000
    assert tool_context.tool_call_id == started.tool_call_id
    assert tool_context.correlation_id == started.correlation_id
    _ = :sys.get_state(context.authority)
    {worker, started}
  end

  defp room(context) do
    speech = %{
      provider: "morse",
      model: Map.get(context, :native_model, "morse"),
      options: %{unit_duration_ms: 20}
    }

    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Test tools.",
          tools: %{
            "lifecycle" => %{
              type: "host",
              tool: "lifecycle",
              conversation_mode: Map.get(context, :conversation_mode, "blocking")
            },
            "background" => %{type: "host", tool: "background", conversation_mode: "non_blocking"},
            "current_time" => %{type: "platform", tool: "get_current_time"},
            "end_call" => %{type: "platform", tool: "hangup"}
          },
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{speech_to_speech: speech}
        }
      }
    }

    permissions = Map.get(context, :variables, [])

    source =
      if permissions == [] do
        source
      else
        source
        |> Map.put(:call_variables, %{
          sections: %{
            "intake" => %{
              schema: %{
                "type" => "object",
                "properties" => %{"note" => %{"type" => "string"}},
                "additionalProperties" => false
              }
            },
            "private" => %{
              schema: %{
                "type" => "object",
                "properties" => %{"note" => %{"type" => "string"}},
                "additionalProperties" => false
              }
            }
          }
        })
        |> put_in([:participants, "assistant", :variable_permissions], %{"intake" => permissions})
      end

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-lifecycle", revision: 1)

    initial =
      if permissions == [],
        do: %{},
        else: %{"intake" => %{"note" => "known"}, "private" => %{"note" => "hidden"}}

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "sts-lifecycle", revision: 1},
                 transport: %{type: "web"},
                 initial_variables: initial
               },
               tenant_id: "tenant-sts-lifecycle",
               actor_id: "actor"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{
               host_tools: %{
                 "lifecycle" => CallEngine.STSLifecycleTool,
                 "background" => CallEngine.STSBackgroundTool
               }
             })

    {:ok, _} =
      Registry.register(CallEngine.RoomRegistry, {CallEngine.STSLifecycleTool, plan.room_id}, nil)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} = TestTransferConnection.attach(command, sink, input_track: @track)
    TestCallStartup.await_ready(plan.room_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    %{authority: authority, capability: capability, room: room}
  end
end
