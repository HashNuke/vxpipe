defmodule Vxpipe.Gateway.SessionAdmissionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor, Session, SessionSupervisor}

  test "managed sessions register before issuance and wait for successful admission release" do
    room = create_room()
    {binding, tracker} = managed_binding(room)
    counter = :atomics.new(1, [])
    owner = self()

    release = fn ->
      attempt = :atomics.add_get(counter, 1, 1)
      send(owner, {:managed_release, attempt})
      if attempt == 1, do: {:error, :unavailable}, else: :ok
    end

    assert {:ok, snapshot} =
             SessionSupervisor.issue(Keyword.put(binding, :release_admission, release), 60_000)

    [{session, _}] = Registry.lookup(Vxpipe.Gateway.SessionRegistry, snapshot.session_id)
    assert snapshot.admission_owner == session
    assert Map.get(snapshot, :cleanup_binding) == Keyword.fetch!(binding, :cleanup_binding)
    refute Map.has_key?(Vxpipe.Gateway.Session.Snapshot.to_public(snapshot), "cleanup_binding")

    assert {:ok, %{resources: %{^session => %{owner: ^session, acknowledgement: :pending}}}} =
             CallCleanup.observe(tracker)

    monitor = Process.monitor(session)
    end_room(room)
    assert_receive {:managed_release, 1}, 1_000

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{engine_outcome: :complete, status: :pending}},
                   1_000

    assert %{status: :pending} = CallCleanup.snapshot(tracker)
    assert {:error, :already_claimed} = Session.claim(snapshot.session_id)
    send(session, :release_admission)
    assert_receive {:managed_release, 2}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
    assert_receive {:call_cleanup_changed, ^tracker, %{status: :complete}}, 1_000
  end

  test "managed normal sessions retain ownership after expiry until their connection exits" do
    room = create_room()
    {binding, tracker} = managed_binding(room)
    assert {:ok, snapshot} = SessionSupervisor.issue(binding, 60_000)
    [{session, _}] = Registry.lookup(Vxpipe.Gateway.SessionRegistry, snapshot.session_id)
    assert snapshot.admission_owner == session
    assert {:ok, _} = Session.claim(snapshot.session_id)
    connection = start_supervised!({Agent, fn -> :connection end})
    assert :ok = Session.bind_connection(snapshot.session_id, connection)
    send(session, :expire)
    assert %Vxpipe.Gateway.Session.Snapshot{} = Session.snapshot(session)

    assert %{resources: %{^session => %{acknowledgement: :pending}}} =
             CallCleanup.snapshot(tracker)

    monitor = Process.monitor(session)
    Agent.stop(connection)
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000

    assert %{resources: %{^session => %{acknowledgement: :complete}}} =
             CallCleanup.snapshot(tracker)
  end

  test "missing or sealed cleanup ownership rejects issuance but releases an owned admission" do
    for unavailable <- [:missing, :sealed] do
      room = create_room()
      {binding, tracker} = managed_binding(room)
      if unavailable == :sealed, do: CallCleanup.seal(tracker)

      if unavailable == :missing,
        do: DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)

      owner = self()

      release = fn ->
        send(owner, {:registration_release, unavailable})
        :ok
      end

      assert {:error, :session_start_failed} =
               SessionSupervisor.issue(Keyword.put(binding, :release_admission, release), 60_000)

      assert_receive {:registration_release, ^unavailable}, 1_000
      assert {:error, :session_start_failed} = SessionSupervisor.issue(binding, 60_000)
    end
  end

  test "tracker loss closes managed credentials without recreating membership" do
    room = create_room()
    {binding, tracker} = managed_binding(room)
    assert {:ok, snapshot} = SessionSupervisor.issue(binding, 60_000)
    [{session, _}] = Registry.lookup(Vxpipe.Gateway.SessionRegistry, snapshot.session_id)
    monitor = Process.monitor(session)
    DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
    assert {:error, :not_found} = Session.claim(snapshot.session_id)

    assert {:error, :not_found} =
             CallCleanupSupervisor.lookup(Keyword.fetch!(binding, :cleanup_binding))
  end

  test "issuance requires the exact live tenant, room and incarnation" do
    room = create_room()
    binding = session_binding(room)

    for invalid <- [
          Keyword.put(binding, :tenant_id, "foreign-tenant"),
          Keyword.put(binding, :room_id, "missing-room"),
          Keyword.put(binding, :incarnation_id, "stale-incarnation")
        ] do
      assert {:error, :session_start_failed} = SessionSupervisor.issue(invalid, 60_000)
    end
  end

  test "room termination closes normal credentials and rejects further issuance" do
    room = create_room()
    assert {:ok, snapshot} = SessionSupervisor.issue(session_binding(room), 60_000)
    [{session, _}] = Registry.lookup(Vxpipe.Gateway.SessionRegistry, snapshot.session_id)
    monitor = Process.monitor(session)
    end_room(room)
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000

    assert {:error, :not_found} = Session.claim(snapshot.session_id)

    assert {:error, :session_start_failed} =
             SessionSupervisor.issue(session_binding(room), 60_000)
  end

  test "room termination denies pending admission claims while release retries" do
    owner = self()
    room = create_room()
    counter = :atomics.new(1, [])

    session =
      start_session(
        fn ->
          attempt = :atomics.add_get(counter, 1, 1)
          send(owner, {:room_release, attempt})
          if attempt == 1, do: {:error, :unavailable}, else: :ok
        end,
        room
      )

    snapshot = Session.snapshot(session)
    monitor = Process.monitor(session)
    end_room(room)
    assert_receive {:room_release, 1}, 1_000
    assert {:error, :already_claimed} = Session.claim(snapshot.session_id)
    send(session, :release_admission)
    assert_receive {:room_release, 2}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "room termination releases admission even while the bound connection remains" do
    owner = self()
    room = create_room()

    session =
      start_session(
        fn ->
          send(owner, :room_admission_released)
          :ok
        end,
        room
      )

    snapshot = Session.snapshot(session)
    assert {:ok, _} = Session.claim(snapshot.session_id)
    connection = start_supervised!({Agent, fn -> :connection end})
    assert :ok = Session.bind_connection(snapshot.session_id, connection)
    monitor = Process.monitor(session)
    end_room(room)
    assert_receive :room_admission_released, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
    assert Agent.get(connection, & &1) == :connection
  end

  test "failed room issuance retains ownership of retryable admission release" do
    owner = self()
    room = create_room()
    counter = :atomics.new(1, [])

    release = fn ->
      attempt = :atomics.add_get(counter, 1, 1)
      send(owner, {:failed_issue_release, self(), attempt})
      if attempt == 1, do: {:error, :unavailable}, else: :ok
    end

    invalid =
      room
      |> session_binding()
      |> Keyword.put(:incarnation_id, "stale-incarnation")
      |> Keyword.put(:release_admission, release)

    assert {:error, :session_start_failed} = SessionSupervisor.issue(invalid, 60_000)
    assert_receive {:failed_issue_release, session, 1}, 1_000
    monitor = Process.monitor(session)
    send(session, :release_admission)
    assert_receive {:failed_issue_release, ^session, 2}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "claim returns not found when room cleanup stops the session during its call" do
    assert_shutdown_race(:claim)
  end

  test "binding returns not found when room cleanup stops the session during its call" do
    assert_shutdown_race(:bind)
  end

  test "releases a bound admission only when its connection ends, after credential expiry" do
    owner = self()

    session =
      start_session(fn ->
        send(owner, :admission_released)
        :ok
      end)

    snapshot = Session.snapshot(session)
    assert {:ok, _} = Session.claim(snapshot.session_id)
    connection = start_supervised!({Agent, fn -> :connection end})
    assert :ok = Session.bind_connection(snapshot.session_id, connection)
    send(session, :expire)
    _ = :sys.get_state(session)
    refute_receive :admission_released, 50
    assert {:error, :already_claimed} = Session.claim(snapshot.session_id)
    monitor = Process.monitor(session)
    Agent.stop(connection)
    assert_receive :admission_released, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "expires an unused destination admission without consuming another token" do
    owner = self()

    session =
      start_session(fn ->
        send(owner, :admission_released)
        :ok
      end)

    monitor = Process.monitor(session)
    send(session, :expire)
    assert_receive :admission_released, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "releases a claimed admission when its request owner dies before connection binding" do
    owner = self()

    session =
      start_session(fn ->
        send(owner, :admission_released)
        :ok
      end)

    snapshot = Session.snapshot(session)

    task =
      start_supervised!(
        {Task,
         fn ->
           assert {:ok, _} = Session.claim(snapshot.session_id)
           send(owner, :claimed)

           receive do
             :finish -> :ok
           end
         end}
      )

    assert_receive :claimed
    monitor = Process.monitor(session)
    send(task, :finish)
    assert_receive :admission_released, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "keeps a failed release unavailable and retries the exact admission" do
    owner = self()
    counter = :atomics.new(1, [])

    session =
      start_session(fn ->
        attempt = :atomics.add_get(counter, 1, 1)
        send(owner, {:release_attempt, attempt})
        if attempt == 1, do: {:error, :unavailable}, else: :ok
      end)

    snapshot = Session.snapshot(session)
    monitor = Process.monitor(session)
    send(session, :expire)
    assert_receive {:release_attempt, 1}, 1_000
    assert {:error, :already_claimed} = Session.claim(snapshot.session_id)
    send(session, :release_admission)
    assert_receive {:release_attempt, 2}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 1_000
  end

  test "an unrelated caller cannot bind or abandon the claimed session" do
    owner = self()

    session =
      start_session(fn ->
        send(owner, :admission_released)
        :ok
      end)

    snapshot = Session.snapshot(session)
    assert {:ok, _} = Session.claim(snapshot.session_id)

    task =
      start_supervised!(
        {Task,
         fn ->
           result = Session.bind_connection(snapshot.session_id, self())
           Session.abandon(snapshot.session_id)
           _ = :sys.get_state(session)
           send(owner, {:foreign_bind, result})
         end}
      )

    assert is_pid(task)
    assert_receive {:foreign_bind, {:error, :invalid_claimant}}
    refute_receive :admission_released, 50
    Session.abandon(snapshot.session_id)
    assert_receive :admission_released, 1_000
  end

  defp assert_shutdown_race(operation) do
    owner = self()
    room = create_room()

    session =
      start_session(
        fn ->
          send(owner, :release_waiting)

          receive do
            :finish_release -> :ok
          after
            5_000 -> {:error, :unavailable}
          end
        end,
        room
      )

    snapshot = Session.snapshot(session)
    on_exit(fn -> send(session, :finish_release) end)

    caller =
      start_supervised!(
        {Task,
         fn ->
           if operation == :bind, do: assert({:ok, _} = Session.claim(snapshot.session_id))
           send(owner, :caller_ready)

           receive do
             :call ->
               result =
                 try do
                   case operation do
                     :claim -> Session.claim(snapshot.session_id)
                     :bind -> Session.bind_connection(snapshot.session_id, self())
                   end
                 catch
                   :exit, _reason -> :escaped_exit
                 end

               send(owner, {:session_call_result, result})
           end
         end}
      )

    assert_receive :caller_ready
    caller_monitor = Process.monitor(caller)
    session_monitor = Process.monitor(session)
    end_room(room)
    assert_receive :release_waiting
    assert 1 = :erlang.trace(caller, true, [:send])
    send(caller, :call)
    request = if operation == :claim, do: :claim, else: {:bind_connection, caller}
    assert_receive {:trace, ^caller, :send, {:"$gen_call", _from, ^request}, ^session}, 1_000
    assert 1 = :erlang.trace(caller, false, [:send])
    send(session, :finish_release)
    assert_receive {:session_call_result, {:error, :not_found}}, 1_000
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 1_000
    assert_receive {:DOWN, ^session_monitor, :process, ^session, :normal}, 1_000
  end

  defp managed_binding(room) do
    cleanup = %{
      tenant_key: room.tenant_id,
      call_id: "call-#{room.room_id}",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id
    }

    {:ok, tracker} = CallCleanupSupervisor.start_new(cleanup)
    on_exit(fn -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker) end)
    {Keyword.put(session_binding(room), :cleanup_binding, cleanup), tracker}
  end

  defp start_session(release, room \\ create_room()) do
    start_supervised!(
      {Session,
       [
         session_id: "sess_#{System.unique_integer([:positive])}",
         ttl_ms: 60_000,
         release_admission: release
       ] ++ session_binding(room)}
    )
  end

  defp session_binding(room) do
    [
      tenant_id: room.tenant_id,
      actor_id: "test-actor",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: "test-support",
      tool_visibility: ToolVisibility.hidden()
    ]
  end

  defp create_room(room_id \\ "session-room-#{System.unique_integer([:positive])}") do
    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "test-tenant",
               actor_id: "test-actor",
               room_id: room_id,
               deadline: DateTime.add(DateTime.utc_now(), 60, :second)
             )

    assert {:ok, room} = CallEngine.create_room(command)

    on_exit(fn ->
      CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)
    end)

    room
  end

  defp end_room(room) do
    assert {:ok, completion} =
             CallEngine.monitor_room_completion(room.tenant_id, room.room_id, room.incarnation_id)

    assert :ok = CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^completion, :process, _, _}, 1_000
  end
end
