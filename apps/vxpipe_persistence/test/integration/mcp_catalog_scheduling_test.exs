defmodule Vxpipe.Persistence.Integration.MCPCatalogSchedulingTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :capture_log

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{CatalogRefreshStore, CatalogRefreshWorker, ConnectionStore}
  alias Vxpipe.Persistence.Schema.{MCPConnection, Tenant}
  alias Vxpipe.Persistence.Test.{CatalogJobNode, MCPDatabaseNode}
  alias Vxpipe.MCP.CheckHTTPFixture

  @now ~U[2026-11-08 12:00:00.000000Z]
  @policy [expiry_seconds: 3_600, reschedule_after_seconds: 1_800, batch_size: 100]
  @oban Vxpipe.Persistence.TestCatalogScheduling

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    start_supervised!({Oban, name: @oban, repo: Repo, testing: :manual})

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Concurrent catalog scheduling", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keys} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, oban: @oban, keyring: keys, now: MCPDatabaseNode.clock(@now)]

    {:ok, connection} =
      ConnectionStore.create(
        context,
        tenant.key,
        %{
          endpoint: "https://catalog.example.test/mcp",
          endpoint_identity: "https://catalog.example.test/mcp",
          server_name: "Catalog",
          auth_method: "bearer",
          catalog: []
        },
        %{"token" => "fixture"}
      )

    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      Repo.delete_all(
        from(j in Oban.Job, where: fragment("?->>'tenant' = ?", j.args, ^tenant.key))
      )

      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    %{context: context, tenant: tenant.key, record: record}
  end

  test "independent sweepers commit one enqueue and one scheduling timestamp", data do
    workers = for index <- 1..2, do: sweeper!(data, index)

    backends =
      for {pid, _} <- workers do
        assert_receive {:sweeper_ready, ^pid, backend}, 3_000
        backend
      end

    assert length(Enum.uniq(backends)) == 2
    for {pid, _} <- workers, do: send(pid, :run)

    results =
      for {pid, monitor} <- workers do
        assert_receive {:sweeper_result, ^pid, result}, 3_000
        assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 3_000
        result
      end

    assert Enum.sort(results) == [{:ok, 0}, {:ok, 1}]
    assert length(jobs(data.tenant)) == 1
    assert Repo.get!(MCPConnection, data.record.id).refresh_scheduled_at == @now
  end

  test "a successful Oban uniqueness conflict does not advance scheduling", data do
    {pid, monitor} = sweeper!(data, :conflict)
    assert_receive {:sweeper_ready, ^pid, _}, 3_000
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :engine, :insert_job, :start],
        &__MODULE__.hold_insert/4,
        {self(), pid}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    send(pid, :run)
    assert_receive {:catalog_insert_paused, ^pid, args}, 3_000

    assert {:ok, %Oban.Job{conflict?: false}} = Oban.insert(@oban, CatalogRefreshWorker.new(args))
    send(pid, :continue_insert)
    assert_receive {:sweeper_result, ^pid, {:ok, 0}}, 3_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 3_000
    assert length(jobs(data.tenant)) == 1
    assert Repo.get!(MCPConnection, data.record.id).refresh_scheduled_at == nil
  end

  test "a replacement BEAM rescues the same durable job after its executing node crashes", data do
    first_server = start_supervised!({CheckHTTPFixture, owner: self(), hold: "tools/list"})
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    [job] = jobs(data.tenant)
    {first, first_identity} = catalog_node(0, data.context, first_server, false)
    refute first_identity.os_pid == System.pid()
    assert_receive {:check_http_held, "tools/list"}, 5_000
    assert Repo.get!(Oban.Job, job.id).state == "executing"
    monitor = Process.monitor(first)
    :peer.cast(first, :erlang, :halt, [137])
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 5_000
    assert_receive {:check_http_closed, "tools/list", {:error, :closed}}, 2_000
    assert Repo.get!(Oban.Job, job.id).state == "executing"
    assert Repo.get!(MCPConnection, data.record.id).refreshed_at == nil

    later = Keyword.put(data.context, :now, MCPDatabaseNode.clock(DateTime.add(@now, 1_801)))
    assert {:ok, 0} = CatalogRefreshStore.enqueue_due(later, @policy)

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Oban.Job, job.id),
        attempted_at: DateTime.add(DateTime.utc_now(), -301)
      )
    )

    second_server = start_supervised!({CheckHTTPFixture, owner: self()})
    {second, second_identity} = catalog_node(1, data.context, second_server, true)
    refute second_identity.os_pid == first_identity.os_pid

    assert %{state: "completed", attempt: 2} =
             :peer.call(second, CatalogJobNode, :await_job, [job.id], 10_000)

    assert_receive {:check_http, "DELETE", _}, 1_000
    assert [completed] = jobs(data.tenant)
    assert completed.id == job.id
    assert completed.args == job.args
    saved = Repo.get!(MCPConnection, data.record.id)
    assert saved.refreshed_at == @now
    assert saved.refresh_scheduled_at == @now
  end

  for failure <- [:enqueue, :timestamp] do
    @tag failure: failure
    test "#{failure} failure rolls back the job and timestamp together", data do
      constraint = "catalog_atomicity_#{System.unique_integer([:positive])}"

      {table, check} =
        case data.failure do
          :enqueue ->
            tenant = String.replace(data.tenant, "'", "''")
            {"oban_jobs", "args->>'tenant' <> '#{tenant}'"}

          :timestamp ->
            {"tenant_mcp_connections", "id <> #{data.record.id} OR refresh_scheduled_at IS NULL"}
        end

      Repo.query!("ALTER TABLE #{table} ADD CONSTRAINT #{constraint} CHECK (#{check}) NOT VALID")

      try do
        assert_raise Ecto.ConstraintError, fn ->
          CatalogRefreshStore.enqueue_due(data.context, @policy)
        end
      after
        Repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{constraint}")
      end

      assert jobs(data.tenant) == []
      assert Repo.get!(MCPConnection, data.record.id).refresh_scheduled_at == nil
    end
  end

  def hold_insert(_event, _measurements, metadata, {owner, sweeper}) do
    if self() == sweeper do
      send(
        owner,
        {:catalog_insert_paused, self(), Ecto.Changeset.get_field(metadata.changeset, :args)}
      )

      receive do
        :continue_insert -> :ok
      after
        5_000 -> send(owner, :catalog_insert_barrier_timeout)
      end
    end
  end

  defp sweeper!(data, id) do
    observer = self()

    pid =
      start_supervised!(
        {Task,
         fn ->
           :ok = Sandbox.checkout(Repo, sandbox: false)
           %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
           send(observer, {:sweeper_ready, self(), backend})

           receive do
             :run ->
               send(
                 observer,
                 {:sweeper_result, self(), CatalogRefreshStore.enqueue_due(data.context, @policy)}
               )
           after
             5_000 -> send(observer, :sweeper_start_timeout)
           end

           Sandbox.checkin(Repo)
         end},
        id: {:catalog_sweeper, id}
      )

    {pid, Process.monitor(pid)}
  end

  defp jobs(tenant),
    do: Repo.all(from(j in Oban.Job, where: fragment("?->>'tenant' = ?", j.args, ^tenant)))

  defp catalog_node(index, context, server, rescue?) do
    peer =
      start_supervised!(%{
        id: {:catalog_node, index},
        start:
          {:peer, :start_link,
           [
             %{
               connection: :standard_io,
               args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()],
               wait_boot: 30_000
             }
           ]},
        restart: :temporary
      })

    identity =
      :peer.call(
        peer,
        CatalogJobNode,
        :boot,
        [Repo.config(), context, CheckHTTPFixture.endpoint(server), rescue?],
        30_000
      )

    {peer, identity}
  end
end
