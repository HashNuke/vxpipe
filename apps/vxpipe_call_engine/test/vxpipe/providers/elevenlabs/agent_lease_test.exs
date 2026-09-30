defmodule Vxpipe.Providers.ElevenLabs.AgentLeaseTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.TestElevenLabsAgentLeaseAPI, as: API
  alias Vxpipe.Providers.ElevenLabs.{AgentAPI, AgentLease, AgentLeaseSupervisor}

  test "preparation returns before remote creation and release waits for explicit cleanup evidence" do
    supervisor = start_supervisor()
    lease = acquire(supervisor, self())
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    refute_received {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}
    send(request, :agent_created)
    assert_receive {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, connection}}, 1_000
    refute inspect(connection) =~ "synthetic-private-token"
    refute inspect(:sys.get_status(lease), limit: :infinity) =~ "synthetic-private-key"
    monitor = Process.monitor(lease)
    assert :ok = AgentLease.release(lease)
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    refute_received {:vxpipe_elevenlabs_agent_lease, ^lease, {:finished, _}}
    send(request, :agent_deleted)
    assert_receive {:vxpipe_elevenlabs_agent_lease, ^lease, {:finished, :released}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^lease, :normal}, 1_000
  end

  test "owner death retires a prepared remote agent outside the owner's supervisor" do
    supervisor = start_supervisor()
    owner = start_owner()
    lease = acquire(supervisor, owner)
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    send(request, :agent_created)
    assert_receive {:forwarded, {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}}, 1_000
    monitor = Process.monitor(lease)
    Process.exit(owner, :kill)
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    send(request, :agent_deleted)
    assert_receive {:DOWN, ^monitor, :process, ^lease, :normal}, 1_000
  end

  test "death during creation still deletes the returned resource without publishing readiness" do
    supervisor = start_supervisor()
    owner = start_owner()
    lease = acquire(supervisor, owner)
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    monitor = Process.monitor(lease)
    owner_monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :killed}, 1_000
    _ = :sys.get_state(lease)
    send(request, :agent_created)
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    refute_received {:forwarded, {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}}
    send(request, :agent_deleted)
    assert_receive {:DOWN, ^monitor, :process, ^lease, :normal}, 1_000
  end

  test "cleanup failure remains observable after owner death without exposing private state" do
    supervisor = start_supervisor()
    owner = start_owner()
    lease = acquire(supervisor, owner)
    watch_outcome(lease)
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    send(request, :agent_created)
    assert_receive {:forwarded, {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}}, 1_000
    Process.exit(owner, :kill)
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    send(request, :agent_delete_failed)

    assert_receive {:lease_outcome, %{count: 1}, %{lease: ^lease, outcome: :cleanup_failed}},
                   1_000
  end

  test "graceful supervisor shutdown permits checked remote deletion before request termination" do
    supervisor = start_supervisor()
    lease = acquire(supervisor, self())
    watch_outcome(lease)
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    send(request, :agent_created)
    assert_receive {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}, 1_000
    supervisor_monitor = Process.monitor(supervisor)
    request_monitor = Process.monitor(request)

    start_supervised!(%{
      id: make_ref(),
      restart: :temporary,
      start: {Task, :start_link, [fn -> Supervisor.stop(supervisor, :normal, :infinity) end]}
    })

    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    refute_received {:DOWN, ^request_monitor, :process, ^request, _}
    refute_received {:DOWN, ^supervisor_monitor, :process, ^supervisor, _}
    send(request, :agent_deleted)
    assert_receive {:lease_outcome, %{count: 1}, %{lease: ^lease, outcome: :owner_lost}}, 1_000
    assert_receive {:DOWN, ^supervisor_monitor, :process, ^supervisor, :normal}, 1_000
  end

  test "installed runtime supervision owns the real API create/sign/delete operation" do
    observer = self()

    plug = fn conn ->
      assert Plug.Conn.get_req_header(conn, "xi-api-key") == ["synthetic-private-key"]
      send(observer, {:native_agent_request, self(), conn.method, conn.request_path})

      case conn.method do
        "POST" ->
          assert conn.request_path == "/v1/convai/agents/create"
          Req.Test.json(conn, %{"agent_id" => "agent_synthetic"})

        "GET" ->
          assert conn.request_path == "/v1/convai/conversation/get-signed-url"
          assert conn.query_params == %{"agent_id" => "agent_synthetic"}

          Req.Test.json(conn, %{
            "signed_url" =>
              "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=agent_synthetic&conversation_signature=synthetic-private-token"
          })

        "DELETE" ->
          assert conn.request_path == "/v1/convai/agents/agent_synthetic"

          receive do
            :confirm_deletion -> Plug.Conn.send_resp(conn, 204, "")
          after
            2_000 -> Plug.Conn.send_resp(conn, 503, "")
          end
      end
    end

    assert {:ok, client} = AgentAPI.new("synthetic-private-key")
    client = %{client | request: Req.merge(client.request, plug: plug)}
    owner = start_owner()
    assert {:ok, lease} = AgentLeaseSupervisor.acquire(owner, client, %{"name" => "Synthetic"})
    watch_outcome(lease)
    monitor = Process.monitor(lease)
    assert_receive {:native_agent_request, request, "POST", _}, 1_000
    assert_receive {:native_agent_request, ^request, "GET", _}, 1_000
    assert_receive {:forwarded, {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}}, 1_000
    refute_received {:native_agent_request, ^request, "DELETE", _}
    Process.exit(owner, :kill)
    assert_receive {:native_agent_request, ^request, "DELETE", _}, 1_000
    refute_received {:lease_outcome, _, _}
    send(request, :confirm_deletion)
    assert_receive {:lease_outcome, %{count: 1}, %{lease: ^lease, outcome: :owner_lost}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^lease, :normal}, 1_000
  end

  test "release is idempotent after checked deletion retires the lease" do
    lease = acquire(start_supervisor(), self())
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    send(request, :agent_created)
    assert_receive {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}, 1_000
    monitor = Process.monitor(lease)
    assert :ok = AgentLease.release(lease)
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    send(request, :agent_deleted)
    assert_receive {:DOWN, ^monitor, :process, ^lease, :normal}, 1_000
    assert :ok = AgentLease.release(lease)
  end

  test "hard lease-controller death still deletes through its independent request owner" do
    lease = acquire(start_supervisor(), self())
    watch_outcome(lease)
    assert_receive {:elevenlabs_agent_create, request}, 1_000
    send(request, :agent_created)
    assert_receive {:vxpipe_elevenlabs_agent_lease, ^lease, {:ready, _}}, 1_000
    monitor = Process.monitor(lease)
    Process.exit(lease, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^lease, :killed}, 1_000
    assert_receive {:elevenlabs_agent_delete, ^request}, 1_000
    send(request, :agent_deleted)
    assert_receive {:lease_outcome, %{count: 1}, %{lease: ^lease, outcome: :owner_lost}}, 1_000
  end

  defp watch_outcome(lease) do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :providers, :elevenlabs, :agent_lease, :finished],
        &__MODULE__.capture_outcome/4,
        {self(), lease}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  def capture_outcome(_event, measurements, %{lease: lease} = metadata, {observer, lease}),
    do: send(observer, {:lease_outcome, measurements, metadata})

  def capture_outcome(_event, _measurements, _metadata, _config), do: :ok

  defp start_supervisor do
    name = {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, make_ref()}}}
    start_supervised!({AgentLeaseSupervisor, name: name})
  end

  defp acquire(supervisor, owner) do
    assert {:ok, lease} =
             AgentLeaseSupervisor.acquire(
               owner,
               %{observer: self(), api_key: "synthetic-private-key"},
               %{"name" => "Synthetic private definition"},
               supervisor: supervisor,
               api_module: API
             )

    lease
  end

  defp start_owner do
    observer = self()

    start_supervised!(%{
      id: make_ref(),
      restart: :temporary,
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               message -> send(observer, {:forwarded, message})
             end

             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end
end
