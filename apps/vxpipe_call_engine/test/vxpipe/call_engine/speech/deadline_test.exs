defmodule Vxpipe.CallEngine.Speech.DeadlineTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Input, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechSessionProbe}

  setup do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    {:ok, owner: owner, scope: CapabilityTree.scope(tree), tasks: tasks}
  end

  test "a delayed close returns timeout and cannot close later after its deadline", context do
    allocation = start(context, provider: MorseSession)
    :ok = :sys.suspend(context.scope.control)
    job = invoke(context, fn -> Session.close(allocation) end)

    try do
      assert_receive {:operation_result, {:error, :close_timeout}}, 300
    after
      :ok = :sys.resume(context.scope.control)
      Task.await(job, 5_000)
    end

    _ = :sys.get_state(context.scope.control)

    assert :ok =
             SpeechSessionOwner.run(context.owner, fn _ ->
               Session.push_audio(allocation, <<0, 0>>)
             end)
  end

  test "input timeout retires owned work without a fresh scope-control cleanup wait", context do
    allocation =
      start(context,
        provider: SpeechSessionProbe,
        private: [observer: self(), hold_input?: true, trap_exits?: true]
      )

    assert_receive {:probe_initializing, provider, _channel}
    provider_monitor = Process.monitor(provider)
    tree = Session.tree(allocation)
    tree_monitor = Process.monitor(tree)
    :ok = :sys.suspend(context.scope.control)
    job = invoke(context, fn -> Session.push_audio(allocation, <<0, 0>>) end)

    try do
      assert_receive {:probe_input, ^provider}
      assert_receive {:operation_result, {:error, :session_failed}}, 300
      assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 300
      assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 300
    after
      :ok = :sys.resume(context.scope.control)
      Task.await(job, 5_000)
    end
  end

  test "input admission wait consumes its existing command budget", context do
    allocation = start(context, provider: MorseSession)
    channel = Channel.address(allocation)
    :ok = :sys.suspend(channel)
    job = invoke(context, fn -> Session.push_audio(allocation, <<0, 0>>) end)

    try do
      assert_receive {:operation_result, {:error, :command_timeout}}, 300
    after
      :ok = :sys.resume(channel)
      Task.await(job, 5_000)
    end

    _ = :sys.get_state(channel)

    assert :ok =
             SpeechSessionOwner.run(context.owner, fn _ ->
               Session.push_audio(allocation, <<0, 0>>)
             end)
  end

  test "held startup admission cannot block close or expiry processing", context do
    active = start(context, provider: MorseSession)
    :ok = :sys.suspend(context.scope.admissions)

    try do
      assert {:ok, pending, :starting} =
               Session.start(context.scope,
                 provider: SpeechSessionProbe,
                 start_timeout: 35,
                 private: [observer: self()]
               )

      assert :ok = SpeechSessionOwner.run(context.owner, fn _ -> Session.close(active) end)
      assert_receive {:vxpipe_speech_closed, ^pending, :startup_timeout}, 300
    after
      :ok = :sys.resume(context.scope.admissions)
    end

    _ = :sys.get_state(context.scope.admissions)
    _ = :sys.get_state(context.scope.control)
    refute_received {:probe_initializing, _provider, _channel}
    replacement = start(context, provider: MorseSession)

    assert :ok =
             SpeechSessionOwner.run(context.owner, fn _ ->
               Session.push_audio(replacement, <<0, 0>>)
             end)
  end

  for held <- [:channel, :control] do
    @held held
    test "adoption cannot commit after waiting past its operation deadline in #{held}", context do
      consumer = self()
      lease = context.owner

      {:ok, allocation, :starting} =
        Session.start(context.scope,
          provider: MorseSession,
          owner: consumer,
          lease: lease,
          consumer: nil,
          call_timeout: 35
        )

      assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}
      held = if @held == :channel, do: Channel.address(allocation), else: context.scope.control
      :ok = :sys.suspend(held)
      job = invoke(context, fn -> Session.adopt(allocation, consumer) end)

      try do
        assert_receive {:operation_result, {:error, :command_timeout}}, 300
      after
        :ok = :sys.resume(held)
        Task.await(job, 5_000)
      end

      _ = :sys.get_state(Channel.address(allocation))
      _ = :sys.get_state(context.scope.control)
      refute_received {:vxpipe_speech, _event}
      assert :ok = SpeechSessionOwner.run(lease, fn _ -> Session.adopt(allocation, consumer) end)
      assert_receive {:vxpipe_speech, ready}
      assert :ok = Session.ack(allocation, ready)
    end
  end

  test "invalid operation budgets are rejected before allocating a slot", context do
    for option <- [:call_timeout, :start_timeout], value <- [0, -1, :infinity, nil, "35"] do
      assert {:error, :invalid_configuration} =
               Session.start(context.scope, [{option, value}, {:provider, MorseSession}])
    end

    assert {:error, :invalid_configuration} =
             Session.start(context.scope, provider: MorseSession, call_timeout: 5_001)

    assert DynamicSupervisor.which_children(context.scope.sessions) == []
  end

  test "unexpected provider returns cannot leak details or retain input authority", context do
    allocation =
      start(context,
        provider: SpeechSessionProbe,
        private: [observer: self(), input_result: {:error, {:upstream, "synthetic-secret"}}]
      )

    provider = Session.provider(allocation)
    monitor = Process.monitor(provider)

    assert {:error, :session_failed} =
             SpeechSessionOwner.run(
               context.owner,
               fn _ -> Session.push_audio(allocation, <<0, 0>>) end
             )

    assert {:error, :closed} =
             SpeechSessionOwner.run(
               context.owner,
               fn _ -> Session.push_audio(allocation, <<0, 0>>) end
             )

    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 300
  end

  test "a suspended input worker expires without sending audio and preserves its sibling",
       context do
    sibling = start(context, provider: MorseSession)
    allocation = start(context, provider: SpeechSessionProbe, private: [observer: self()])
    assert_receive {:probe_initializing, provider, _channel}
    input = GenServer.whereis(Input.address(allocation))
    tree = Session.tree(allocation)
    monitors = for pid <- [input, provider, tree], do: {pid, Process.monitor(pid)}
    :ok = :sys.suspend(input)

    assert {:error, :session_failed} =
             SpeechSessionOwner.run(
               context.owner,
               fn _ -> Session.push_audio(allocation, <<0, 0>>) end
             )

    for {pid, monitor} <- monitors,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, _reason}, 300)

    refute_received {:probe_input, ^provider}

    assert :ok =
             SpeechSessionOwner.run(context.owner, fn _ ->
               Session.push_audio(sibling, <<0, 0>>)
             end)
  end

  test "an adoption committed while its channel is held cannot deliver late readiness", context do
    consumer = self()
    lease = context.owner

    {:ok, allocation, :starting} =
      Session.start(context.scope,
        provider: MorseSession,
        owner: consumer,
        lease: lease,
        consumer: nil,
        call_timeout: 35
      )

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}
    channel = GenServer.whereis(Channel.address(allocation))
    tree = Session.tree(allocation)
    monitor = Process.monitor(tree)
    observer = self()

    debug = fn state, event, _extra ->
      case event do
        {:in, {:"$gen_call", _from, {:activate, _, _, _, _}}} ->
          send(observer, :activation_waiting)

          receive do
            :release_activation -> :ok
          end

          state

        {:out, :ok, _from, new_state} ->
          if Enum.any?(new_state.entries, fn {_id, entry} -> entry.phase == :active end) do
            send(observer, :activation_committed)
            :done
          else
            state
          end

        _ ->
          state
      end
    end

    :ok = :sys.install(context.scope.control, {debug, nil})
    job = invoke(context, fn -> Session.adopt(allocation, consumer) end)
    assert_receive :activation_waiting
    :erlang.suspend_process(channel)

    try do
      send(context.scope.control, :release_activation)
      assert_receive :activation_committed
      assert_receive {:operation_result, {:error, :command_timeout}}, 300
    after
      try do
        :erlang.resume_process(channel)
      rescue
        ArgumentError -> :ok
      end

      Task.await(job, 5_000)
    end

    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 300
    refute_received {:vxpipe_speech, _event}
  end

  test "close observes a tree created after its initial lookup", context do
    :ok = :sys.suspend(context.scope.admissions)

    {:ok, allocation, :starting} =
      Session.start(context.scope, provider: MorseSession, owner: context.owner, call_timeout: 35)

    observer = self()

    debug = fn state, event, _extra ->
      case event do
        {:in, {:"$gen_call", _from, {:close, _, _, _}}} ->
          send(observer, :close_waiting)

          receive do
            :release_close -> :ok
          end

          :done

        _ ->
          state
      end
    end

    :ok = :sys.install(context.scope.control, {debug, nil})
    :erlang.trace(context.scope.admissions, true, [:send])
    job = invoke(context, fn -> Session.close(allocation) end)
    assert_receive :close_waiting
    :ok = :sys.resume(context.scope.admissions)

    assert_receive {:trace, _admission, :send, {:"$gen_call", _from, {:bind, ^allocation, tree}},
                    _control}

    :erlang.trace(context.scope.admissions, false, [:send])
    channel = Channel.address(allocation)
    :ok = :sys.suspend(channel)
    monitor = Process.monitor(tree)

    try do
      send(context.scope.control, :release_close)
      assert_receive {:operation_result, {:error, :close_timeout}}, 300
    after
      :ok = :sys.resume(channel)
      Task.await(job, 5_000)
    end

    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 300
  end

  test "direct startup cannot deliver ready after a late activation reply", context do
    observer = self()

    debug = fn state, event, _extra ->
      case event do
        {:in, {:"$gen_call", {channel, _tag}, {:activate, _, _, _, _}}} ->
          send(observer, {:activation_waiting, channel})

          receive do
            :release_activation -> :ok
          end

          state

        {:out, :ok, _from, new_state} ->
          if Enum.any?(new_state.entries, fn {_id, entry} -> entry.phase == :active end) do
            send(observer, :activation_committed)
            :done
          else
            state
          end

        _ ->
          state
      end
    end

    :ok = :sys.install(context.scope.control, {debug, nil})

    {:ok, allocation, :starting} =
      Session.start(context.scope, provider: MorseSession, start_timeout: 100)

    assert_receive {:activation_waiting, channel}
    tree = Session.tree(allocation)
    monitor = Process.monitor(tree)
    :erlang.suspend_process(channel)

    try do
      send(context.scope.control, :release_activation)
      assert_receive :activation_committed
      delay = max(allocation.deadline - System.monotonic_time(:millisecond), 0) + 1
      Process.send_after(self(), :past_deadline, delay)
      assert_receive :past_deadline, 300
    after
      :erlang.resume_process(channel)
    end

    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 300
    refute_received {:vxpipe_speech, _event}
  end

  test "malformed ownership cannot retire an existing sibling", context do
    active = start(context, provider: MorseSession)

    for invalid <- [
          [owner: nil],
          [consumer: nil],
          [consumer: :invalid],
          [consumer: nil, lease: :invalid],
          [lease: self()]
        ] do
      assert {:error, :invalid_configuration} =
               Session.start(
                 context.scope,
                 [provider: MorseSession] ++ invalid
               )
    end

    assert :ok =
             SpeechSessionOwner.run(
               context.owner,
               fn _ -> Session.push_audio(active, <<0, 0>>) end
             )
  end

  test "public reservation timeout invalidates queued private startup", context do
    :ok = :sys.suspend(context.scope.control)

    try do
      assert {:error, :unavailable} =
               Session.start(context.scope,
                 provider: SpeechSessionProbe,
                 start_timeout: 35,
                 private: [observer: self(), secret: "synthetic-queued-private"]
               )
    after
      :ok = :sys.resume(context.scope.control)
    end

    _ = :sys.get_state(context.scope.control)
    _ = :sys.get_state(context.scope.admissions)
    assert :sys.get_state(context.scope.control).entries == %{}
    refute_received {:probe_initializing, _provider, _channel}
    refute inspect(:sys.get_status(context.scope.control)) =~ "synthetic-queued-private"
    _ = start(context, provider: MorseSession)
  end

  defp start(context, options) do
    options = Keyword.merge(options, owner: context.owner, call_timeout: 35)
    {:ok, allocation, :starting} = Session.start(context.scope, options)
    owner = context.owner
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech, ready}}
    assert :ok = SpeechSessionOwner.run(owner, fn _ -> Session.ack(allocation, ready) end)
    allocation
  end

  defp invoke(context, operation) do
    observer = self()

    Task.Supervisor.async_nolink(context.tasks, fn ->
      result = SpeechSessionOwner.run(context.owner, fn _ -> operation.() end)
      send(observer, {:operation_result, result})
    end)
  end
end
