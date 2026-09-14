defmodule Vxpipe.Gateway.SessionAdmissionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.Session

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

  defp start_session(release) do
    start_supervised!(
      {Session,
       [
         session_id: "sess_#{System.unique_integer([:positive])}",
         ttl_ms: 60_000,
         tenant_id: "test-tenant",
         actor_id: "test-actor",
         room_id: "test-room",
         incarnation_id: "test-incarnation",
         participant_id: "test-support",
         tool_visibility: ToolVisibility.hidden(),
         release_admission: release
       ]}
    )
  end
end
