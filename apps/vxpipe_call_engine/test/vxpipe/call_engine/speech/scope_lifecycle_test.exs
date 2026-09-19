defmodule Vxpipe.CallEngine.Speech.ScopeLifecycleTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession

  alias Vxpipe.CallEngine.Speech.{
    Admission,
    CapabilityTree,
    Channel,
    Event,
    Input,
    ScopeControl,
    Session,
    SessionTree
  }

  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechSessionProbe}

  test "expiry before adoption preserves the original deadline and rejects a late handoff" do
    scope = scope()
    lease = start_supervised!({SpeechSessionOwner, self()})
    consumer = self()

    {:ok, allocation, :starting} =
      SpeechSessionOwner.run(lease, fn _state ->
        Session.start(scope,
          provider: MorseSession,
          owner: consumer,
          lease: self(),
          consumer: nil,
          start_timeout: 100
        )
      end)

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}

    assert_receive {:speech_owner, ^lease,
                    {:vxpipe_speech_closed, ^allocation, :startup_timeout}},
                   500

    assert {:error, :closed} =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    refute_received {:vxpipe_speech, _event}
  end

  test "lifetime owner death still retires the adopted allocation" do
    scope = scope()
    owner = start_supervised!({SpeechSessionOwner, self()}, id: :owner)
    lease = start_supervised!({SpeechSessionOwner, self()}, id: :lease)
    consumer = self()

    {:ok, allocation, :starting} =
      SpeechSessionOwner.run(lease, fn _state ->
        Session.start(scope, provider: MorseSession, owner: owner, lease: self(), consumer: nil)
      end)

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}

    assert :ok =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(allocation, ready)
    tree = Session.tree(allocation)
    monitor = Process.monitor(tree)
    GenServer.stop(owner)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}
    assert_receive {:vxpipe_speech_closed, ^allocation, :owner_lost}
  end

  test "adopted provider failure reaches the current consumer exactly once" do
    scope = scope()
    lease = start_supervised!({SpeechSessionOwner, self()})
    allocation = prepare(scope, lease)
    consumer = self()

    assert :ok =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(allocation, ready)
    tree = Session.tree(allocation)
    monitor = Process.monitor(tree)
    Process.exit(Session.provider(allocation), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}
    assert_receive {:vxpipe_speech_closed, ^allocation, :session_failed}
    _ = :sys.get_state(scope.control)
    refute_received {:vxpipe_speech_closed, ^allocation, _reason}

    assert :ok = SpeechSessionOwner.run(lease, fn _state -> :ok end)
    refute_received {:speech_owner, ^lease, {:vxpipe_speech_closed, ^allocation, _reason}}
  end

  test "adopted consumer death retires descendants while its lifetime owner remains" do
    scope = scope()
    lease = start_supervised!({SpeechSessionOwner, self()}, id: :lease)
    consumer = start_supervised!({SpeechSessionOwner, self()}, id: :consumer)
    allocation = prepare(scope, lease)

    assert :ok =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    tree = Session.tree(allocation)
    provider = Session.provider(allocation)
    tree_monitor = Process.monitor(tree)
    provider_monitor = Process.monitor(provider)
    GenServer.stop(consumer)
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 500
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 500
    assert :ok = Session.push_audio(start_morse(scope), <<0, 0>>)
  end

  test "lease cancellation before adoption prevents later activation" do
    scope = scope()
    lease = start_supervised!({SpeechSessionOwner, self()})
    allocation = prepare(scope, lease)
    consumer = self()
    assert :ok = SpeechSessionOwner.run(lease, fn _state -> Session.close(allocation) end)

    assert {:error, :closed} =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    refute_received {:vxpipe_speech, _event}
  end

  test "changing ownership fields in a handle does not grant close authority" do
    scope = scope()
    owner = start_supervised!({SpeechSessionOwner, self()})
    {:ok, allocation, :starting} = Session.start(scope, provider: MorseSession, owner: owner)
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech, ready}}
    assert :ok = SpeechSessionOwner.run(owner, fn _state -> Session.ack(allocation, ready) end)
    assert {:error, :not_owner} = Session.close(%{allocation | owner: self(), consumer: self()})

    assert :ok =
             SpeechSessionOwner.run(owner, fn _state ->
               Session.push_audio(allocation, <<0, 0>>)
             end)
  end

  test "prepared readiness precedes adoption, which transfers authority without reparenting" do
    scope = scope()
    owner = start_supervised!({SpeechSessionOwner, self()}, id: :lifetime_owner)
    lease = start_supervised!({SpeechSessionOwner, self()}, id: :lease_authority)
    consumer = self()

    {:ok, allocation, :starting} =
      SpeechSessionOwner.run(lease, fn _state ->
        Session.start(scope, provider: MorseSession, owner: owner, lease: self(), consumer: nil)
      end)

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}

    tree = Session.tree(allocation)
    refute_received {:vxpipe_speech, _event}
    assert {:error, :not_owner} = Session.push_audio(allocation, <<0, 0>>)

    assert :ok =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}
    assert :ok = Session.ack(allocation, ready)
    assert Session.tree(allocation) == tree
    tree_monitor = Process.monitor(tree)
    old_lease_close = SpeechSessionOwner.run(lease, fn _state -> Session.close(allocation) end)
    active_input = Session.push_audio(allocation, <<0, 0>>)

    tree_state =
      receive do
        {:DOWN, ^tree_monitor, :process, ^tree, _reason} -> :terminated
      after
        0 -> :no_termination_observed
      end

    Process.demonitor(tree_monitor, [:flush])

    assert {old_lease_close, active_input, tree_state} ==
             {{:error, :not_owner}, :ok, :no_termination_observed}

    GenServer.stop(lease)
    assert :ok = Session.push_audio(allocation, <<0, 0>>)
    assert :ok = Session.close(allocation)
  end

  test "an activated allocation remains usable after its startup deadline" do
    scope = scope()

    assert {:ok, allocation, :starting} =
             Session.start(scope, provider: MorseSession, start_timeout: 80)

    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}
    assert :ok = Session.ack(allocation, ready)
    Process.send_after(self(), :past_startup_deadline, 100)
    assert_receive :past_startup_deadline, 500
    assert :ok = Session.push_audio(allocation, <<0, 0>>)
    refute_received {:vxpipe_speech_closed, ^allocation, _reason}
  end

  test "owner loss before bind reaps the exact trapping initializer" do
    scope = scope()
    owner = start_supervised!({SpeechSessionOwner, self()})

    assert {:ok, allocation, :starting} =
             Session.start(scope,
               provider: SpeechSessionProbe,
               owner: owner,
               start_timeout: 200,
               private: [observer: self(), hold_before_bind?: true, trap_exits?: true]
             )

    assert_receive {:probe_before_bind, provider, _channel}
    tree = Session.tree(allocation)
    provider_monitor = Process.monitor(provider)
    tree_monitor = Process.monitor(tree)
    GenServer.stop(owner)
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 500
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 500
    refute_received {:vxpipe_speech, _event}
  end

  test "an explicit scope admits a ready allocation and closes only that generation" do
    scope = scope()
    first = start_morse(scope)
    first_tree = Session.tree(first)
    first_monitor = Process.monitor(first_tree)
    assert :ok = Session.close(first)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_tree, _reason}

    replacement = start_morse(scope)
    assert :ok = Session.close(first)
    assert :ok = Session.push_audio(replacement, <<0, 0>>)
    assert Session.tree(replacement) != first_tree
  end

  test "queued cancellation prevents provider creation after admission resumes" do
    scope = scope()
    :ok = :sys.suspend(scope.sessions)

    try do
      assert {:ok, allocation, :starting} =
               Session.start(scope,
                 provider: SpeechSessionProbe,
                 private: [observer: self()]
               )

      assert :ok = Session.close(allocation)
    after
      :ok = :sys.resume(scope.sessions)
    end

    # A later allocation passes the same admission queue and proves it resumed.
    _replacement = start_morse(scope)
    refute_received {:probe_initializing, _provider, _channel}
  end

  test "queued expiry includes admission wait and cannot start a late provider" do
    scope = scope()
    :ok = :sys.suspend(scope.sessions)

    try do
      assert {:ok, allocation, :starting} =
               Session.start(scope,
                 provider: SpeechSessionProbe,
                 start_timeout: 40,
                 private: [observer: self()]
               )

      assert_receive {:vxpipe_speech_closed, ^allocation, :startup_timeout}, 500
    after
      :ok = :sys.resume(scope.sessions)
    end

    _replacement = start_morse(scope)
    refute_received {:probe_initializing, _provider, _channel}
  end

  test "provider loss retires its allocation while a sibling remains usable" do
    scope = scope()
    active = start_morse(scope)
    candidate = start_morse(scope)
    candidate_tree = Session.tree(candidate)
    monitor = Process.monitor(candidate_tree)
    provider = Session.provider(candidate)
    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^candidate_tree, _reason}
    assert_receive {:vxpipe_speech_closed, ^candidate, :session_failed}
    assert :ok = Session.push_audio(active, <<0, 0>>)
  end

  test "shared session-supervisor loss retires the capability and preserves another scope" do
    failed_scope = scope()
    healthy_scope = scope()
    failed = start_morse(failed_scope)
    healthy = start_morse(healthy_scope)
    capability = failed_scope.tree
    provider = Session.provider(failed)
    capability_monitor = Process.monitor(capability)
    provider_monitor = Process.monitor(provider)
    Process.exit(failed_scope.sessions, :kill)
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _reason}
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
    assert :ok = Session.push_audio(healthy, <<0, 0>>)
  end

  for failure <- [:channel, :input, :initializer_supervisor, :provider_supervisor] do
    @failure failure
    test "#{failure} loss retires only its allocation, with no restart or replay" do
      scope = scope()
      active = start_morse(scope)
      failed = start_morse(scope)
      tree = Session.tree(failed)
      provider = Session.provider(failed)
      descendants = [tree, provider, GenServer.whereis(Input.address(failed))]
      monitors = for pid <- descendants, do: {pid, Process.monitor(pid)}

      target =
        case @failure do
          :channel -> Channel.address(failed)
          :input -> Input.address(failed)
          :initializer_supervisor -> SessionTree.commands(failed)
          :provider_supervisor -> SessionTree.providers(failed)
        end

      Process.exit(GenServer.whereis(target), :kill)

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _reason}, 500)

      assert_receive {:vxpipe_speech_closed, ^failed, :session_failed}
      # Registry may briefly retain an already monitored dead PID.
      assert Session.tree(failed) in [nil, tree]
      assert Session.provider(failed) in [nil, provider]
      assert :ok = Session.push_audio(active, reference_e())
      assert receive_turn(active) == "E"
      _ = :sys.get_state(scope.control)
      refute_received {:vxpipe_speech_closed, ^failed, _reason}
      replacement = start_morse(scope)
      assert :ok = Session.push_audio(replacement, reference_e())
      assert receive_turn(replacement) == "E"
    end
  end

  for failure <- [:control, :admissions] do
    @failure failure
    test "shared #{failure} failure retires its capability while another scope recognizes" do
      scope = scope()
      other = scope()
      failed = start_morse(scope)
      healthy = start_morse(other)

      descendants = [
        scope.tree,
        Session.tree(failed),
        Session.provider(failed),
        GenServer.whereis(Input.address(failed))
      ]

      monitors = for pid <- descendants, do: {pid, Process.monitor(pid)}
      target = if @failure == :control, do: scope.control, else: scope.admissions
      Process.exit(target, :kill)

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _reason}, 500)

      assert :ok = Session.push_audio(healthy, reference_e())
      assert receive_turn(healthy) == "E"
    end
  end

  test "queued private initialization is redacted, discarded on close, and cannot recycle held slots" do
    scope = scope()
    :ok = :sys.suspend(scope.admissions)
    private = [observer: self(), secret: "synthetic-private-initialization"]

    try do
      for _ <- 1..2 do
        {:ok, allocation, :starting} =
          Session.start(scope, provider: SpeechSessionProbe, private: private)

        state = :sys.get_state(scope.control)
        assert Map.fetch!(state.entries, allocation.generation).private == private
        refute inspect(:sys.get_status(scope.control)) =~ "synthetic-private-initialization"
        assert :ok = Session.close(allocation)
        state = :sys.get_state(scope.control)
        assert Map.fetch!(state.entries, allocation.generation).private == nil
      end

      assert {:error, :busy} = Session.start(scope, provider: MorseSession)
    after
      :ok = :sys.resume(scope.admissions)
    end

    _ = :sys.get_state(scope.admissions)
    _ = :sys.get_state(scope.control)
    _replacement = start_morse(scope)
    refute_received {:probe_initializing, _pid, _channel}
  end

  test "private handoff clears the controller and retained supervisor arguments stay opaque" do
    scope = scope()
    sentinel = "synthetic-private-handoff"

    {:ok, allocation, :starting} =
      Session.start(scope,
        provider: SpeechSessionProbe,
        private: [observer: self(), secret: sentinel, hold_before_bind?: true]
      )

    assert_receive {:probe_before_bind, provider, _channel}
    state = :sys.get_state(scope.control)
    assert Map.fetch!(state.entries, allocation.generation).private == nil

    for process <- [
          scope.control,
          scope.tree,
          scope.admissions,
          scope.sessions,
          Session.tree(allocation),
          Channel.address(allocation),
          Input.address(allocation)
        ] do
      refute inspect(:sys.get_status(process)) =~ sentinel
    end

    # Callback redaction also covers abnormal-exit reasons and mailbox messages.
    status = %{state: sentinel, message: sentinel, reason: sentinel, log: [sentinel]}

    for module <- [Admission, ScopeControl, Channel, Input] do
      refute inspect(module.format_status(status)) =~ sentinel
    end

    send(provider, :release_bind)
    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(allocation, ready)
    assert :ok = Session.close(allocation)
  end

  test "all execution children descend from the explicit local scope" do
    scope = scope()
    allocation = start_morse(scope)
    tree = Session.tree(allocation)

    assert Enum.any?(Supervisor.which_children(scope.tree), fn {_id, pid, _, _} ->
             pid == scope.sessions
           end)

    assert [{_id, ^tree, :supervisor, _modules}] =
             DynamicSupervisor.which_children(scope.sessions)

    children = Supervisor.which_children(tree)

    for address <- [
          Channel.address(allocation),
          Input.address(allocation),
          SessionTree.commands(allocation),
          SessionTree.providers(allocation)
        ] do
      pid = GenServer.whereis(address)
      assert Enum.any?(children, fn {_id, child, _, _} -> child == pid end)
    end

    provider = Session.provider(allocation)

    assert [{_id, ^provider, :worker, _modules}] =
             DynamicSupervisor.which_children(SessionTree.providers(allocation))

    assert Process.whereis(Vxpipe.CallEngine.Speech.SessionSupervisor) == nil
    assert Process.whereis(Vxpipe.CallEngine.Speech.Registry) == nil
  end

  defp reference_e do
    dot =
      for i <- 0..959, into: <<>> do
        value = round(12_000 * :math.sin(2 * :math.pi() * 700 * i / 16_000))
        <<value::little-signed-16>>
      end

    dot <> :binary.copy(<<0, 0>>, 13_440)
  end

  defp receive_turn(allocation) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation} = event}
    assert :ok = Session.ack(allocation, event)
    if event.kind == :turn_ended, do: event.text, else: receive_turn(allocation)
  end

  defp scope do
    CapabilityTree
    |> then(&start_supervised!(Supervisor.child_spec({&1, owner: self()}, id: make_ref())))
    |> CapabilityTree.scope()
  end

  defp prepare(scope, lease) do
    owner = self()

    {:ok, allocation, :starting} =
      SpeechSessionOwner.run(lease, fn _state ->
        Session.start(scope, provider: MorseSession, owner: owner, lease: self(), consumer: nil)
      end)

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}}
    allocation
  end

  defp start_morse(scope) do
    assert {:ok, allocation, :starting} = Session.start(scope, provider: MorseSession)
    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}, 1_000
    assert :ok = Session.ack(allocation, ready)
    allocation
  end
end
