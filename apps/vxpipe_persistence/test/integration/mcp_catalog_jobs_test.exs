defmodule Vxpipe.Persistence.Integration.MCPCatalogJobsTest do
  use Vxpipe.Persistence.DataCase, async: false
  @moduletag :integration
  @moduletag :capture_log

  alias Vxpipe.Calls.Administration
  alias Vxpipe.MCP.CheckHTTPFixture
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{CatalogRefreshStore, CatalogRefreshWorker, ConnectionStore}
  alias Vxpipe.Persistence.Schema.MCPConnection
  alias Vxpipe.Persistence.Test.CatalogDiscoveryProtocol

  @now ~U[2026-11-08 12:00:00.000000Z]
  @policy [expiry_seconds: 3_600, reschedule_after_seconds: 1_800, batch_size: 100]
  @oban Vxpipe.Persistence.TestCatalogExecution

  setup do
    start_supervised!({Oban, name: @oban, repo: Repo, testing: :manual})

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Catalog job execution", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, oban: @oban, keyring: keyring, now: fn -> @now end]

    {:ok, connection} =
      ConnectionStore.create(
        context,
        tenant.key,
        %{
          endpoint: "https://catalog.example.test/mcp",
          endpoint_identity: "https://catalog.example.test/mcp",
          server_name: "Old catalog",
          auth_method: "bearer",
          catalog: [%{"name" => "old_tool", "inputSchema" => %{"type" => "object"}}]
        },
        %{"token" => "synthetic-job-token"}
      )

    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))

    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])

    configure(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.merge(configured,
        mcp_catalog_refresh_repository: {CatalogRefreshStore, context},
        mcp_connection_repository: {ConnectionStore, context}
      )
    )

    %{tenant: tenant.key, context: context, connection: connection}
  end

  test "an actual queued job discovers, publishes and closes its independent session", data do
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server)
    baseline = DynamicSupervisor.count_children(Vxpipe.MCP.CheckSupervisor).active
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :mcp_catalog)
    assert_receive {:check_http, "initialize", headers}
    assert {"authorization", "Bearer synthetic-job-token"} in headers
    assert_receive {:check_http, "tools/list", _}
    assert_receive {:check_http, "DELETE", _}

    saved = Repo.get_by!(MCPConnection, public_id: data.connection.id)
    assert saved.catalog == %{"tools" => []}
    assert saved.refreshed_at == @now
    assert saved.refresh_scheduled_at == @now
    assert saved.endpoint == data.connection.endpoint
    assert DynamicSupervisor.count_children(Vxpipe.MCP.CheckSupervisor).active == baseline
    job = Repo.one!(Oban.Job)
    assert job.state == "completed"
    refute inspect(job) =~ "synthetic-job-token"
    refute_received {:check_http_unexpected, _}
  end

  test "a newer manual refresh makes the queued attempt obsolete before protocol work", data do
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    {:ok, before} = ConnectionStore.get_retained(data.context, data.tenant, data.connection.id)

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               before.id,
               1,
               Map.take(before, [:refreshed_at, :refresh_scheduled_at]),
               %{server_name: "Manual catalog", catalog: []}
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :mcp_catalog)
    refute_received {:catalog_job_process, _}
    refute_received {:check_http, _, _}
    assert Repo.get_by!(MCPConnection, public_id: before.id).server_name == "Manual catalog"
  end

  test "a bounded backlog drains across batches and releases all discovery sessions", data do
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server)
    baseline = DynamicSupervisor.count_children(Vxpipe.MCP.CheckSupervisor).active

    for index <- 2..12 do
      endpoint = "https://backlog-#{index}.example.test/mcp"

      {:ok, connection} =
        ConnectionStore.create(
          data.context,
          data.tenant,
          %{
            endpoint: endpoint,
            endpoint_identity: endpoint,
            server_name: "Backlog",
            auth_method: "bearer",
            catalog: []
          },
          %{"token" => "fixture"}
        )

      record = Repo.get_by!(MCPConnection, public_id: connection.id)
      Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))
    end

    policy = Keyword.put(@policy, :batch_size, 5)

    assert for(_ <- 1..4, do: CatalogRefreshStore.enqueue_due(data.context, policy)) ==
             [{:ok, 5}, {:ok, 5}, {:ok, 2}, {:ok, 0}]

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :stop],
        &CatalogDiscoveryProtocol.job_measurements/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    started = System.monotonic_time(:millisecond)
    live_queue!(4)

    measurements =
      for _ <- 1..12 do
        assert_receive {:catalog_job_measurements, _, measurements}, 5_000
        measurements
      end

    elapsed = System.monotonic_time(:millisecond) - started
    assert Repo.aggregate(Oban.Job, :count) == 12
    assert Enum.all?(Repo.all(Oban.Job), &(&1.state == "completed" and &1.attempt == 1))
    assert Enum.all?(Repo.all(MCPConnection), &(&1.refreshed_at == @now))
    assert DynamicSupervisor.count_children(Vxpipe.MCP.CheckSupervisor).active == baseline
    for _ <- 1..12, do: assert_receive({:check_http, "DELETE", _})

    timings =
      for key <- [:queue_time, :duration], into: %{} do
        values =
          Enum.map(
            measurements,
            &System.convert_time_unit(Map.fetch!(&1, key), :native, :microsecond)
          )

        {key, {Enum.min(values), Enum.max(values)}}
      end

    IO.puts(
      "Catalog backlog: 12 jobs, batch 5, concurrency 4, #{elapsed} ms, " <>
        "microsecond ranges #{inspect(timings)}, discovery baseline #{baseline}"
    )
  end

  test "two tenants at the same endpoint discover and retain their own authorized catalogs",
       data do
    first_tool = %{"name" => "first_tenant_tool", "inputSchema" => %{"type" => "object"}}
    second_tool = %{"name" => "second_tenant_tool", "inputSchema" => %{"type" => "object"}}

    server =
      start_supervised!(
        {CheckHTTPFixture,
         owner: self(),
         catalogs_by_authorization: %{
           "Bearer synthetic-job-token" => [first_tool],
           "Bearer other-tenant-token" => [second_tool]
         }}
      )

    protocol(server)

    {:ok, other, _} =
      Administration.bootstrap_tenant("Other catalog tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    attributes =
      Map.take(
        data.connection,
        [:endpoint, :endpoint_identity, :server_name, :auth_method, :catalog]
      )

    {:ok, connection} =
      ConnectionStore.create(data.context, other.key, attributes, %{
        "token" => "other-tenant-token"
      })

    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))

    assert {:ok, 2} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    assert %{success: 2, failure: 0} = Oban.drain_queue(@oban, queue: :mcp_catalog)

    assert Repo.get_by!(MCPConnection, public_id: data.connection.id).catalog == %{
             "tools" => [first_tool]
           }

    assert Repo.get_by!(MCPConnection, public_id: connection.id).catalog == %{
             "tools" => [second_tool]
           }

    assert Enum.sort(Enum.map(Repo.all(Oban.Job), & &1.args["tenant"])) ==
             Enum.sort([data.tenant, other.key])
  end

  test "a failing protocol attempt preserves the snapshot and redacts durable job errors", data do
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server, raise_marker: "synthetic-sensitive-upstream-error")
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    assert %{success: 0, failure: 1} = Oban.drain_queue(@oban, queue: :mcp_catalog)

    saved = Repo.get_by!(MCPConnection, public_id: data.connection.id)
    assert saved.catalog == %{"tools" => data.connection.catalog}
    assert saved.refreshed_at == nil
    assert saved.refresh_scheduled_at == @now
    job = Repo.one!(Oban.Job)
    assert job.state == "retryable"
    assert inspect(job.errors) =~ "mcp_catalog_refresh_failed"
    refute inspect(job.errors) =~ "synthetic-sensitive"
    refute inspect(job) =~ "synthetic-job-token"
  end

  test "a held job result cannot overwrite a newer manual refresh at the same clock time", data do
    live_queue!()
    observe_completion()
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server, hold_result: true)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    assert_receive {:catalog_result_held, worker}, 3_000
    {:ok, before} = ConnectionStore.get_retained(data.context, data.tenant, data.connection.id)

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               before.id,
               1,
               Map.take(before, [:refreshed_at, :refresh_scheduled_at]),
               %{server_name: "Manual winner", catalog: []}
             )

    send(worker, :release_catalog_result)
    assert_receive {:catalog_job_finished, _, _}, 3_000

    saved = Repo.get_by!(MCPConnection, public_id: before.id)
    assert saved.server_name == "Manual winner"
    assert saved.refreshed_at == @now
  end

  test "duplicate delivery publishes only once under a fixed clock", data do
    live_queue!(2)
    observe_completion()
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    protocol(server, hold_result: true)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    original = Repo.one!(Oban.Job)
    assert {:ok, _} = Oban.insert(@oban, CatalogRefreshWorker.new(original.args, unique: false))
    assert_receive {:catalog_result_held, first}, 3_000
    assert_receive {:catalog_result_held, second}, 3_000
    refute first == second
    assert Repo.get_by!(MCPConnection, public_id: data.connection.id).refreshed_at == nil
    send(first, :release_catalog_result)
    assert_receive {:catalog_job_finished, _, _}, 3_000
    assert Repo.get_by!(MCPConnection, public_id: data.connection.id).refreshed_at == @now
    send(second, :release_catalog_result)
    assert_receive {:catalog_job_finished, _, _}, 3_000
    assert Repo.get_by!(MCPConnection, public_id: data.connection.id).refreshed_at == @now
    assert Enum.all?(Repo.all(Oban.Job), &(&1.state == "completed"))
  end

  for change <- [:disconnect, :replace, :delete] do
    @tag connection_change: change
    test "a held job result cannot publish after connection #{change}", data do
      live_queue!()
      observe_completion()
      server = start_supervised!({CheckHTTPFixture, owner: self()})
      protocol(server, hold_result: true)
      assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
      assert_receive {:catalog_result_held, worker}, 3_000

      case data.connection_change do
        :disconnect ->
          assert {:ok, _} =
                   ConnectionStore.revoke(data.context, data.tenant, data.connection.id, 1)

        :replace ->
          attributes =
            data.connection
            |> Map.take([:endpoint, :endpoint_identity, :server_name, :auth_method, :catalog])
            |> Map.put(:server_name, "Replacement")

          assert {:ok, _} =
                   ConnectionStore.replace(
                     data.context,
                     data.tenant,
                     data.connection.id,
                     1,
                     attributes,
                     %{"token" => "new-token"}
                   )

          replaced = Repo.get_by!(MCPConnection, public_id: data.connection.id)
          assert replaced.refresh_scheduled_at == nil
          assert replaced.refreshed_at == @now

        :delete ->
          Repo.delete!(Repo.get_by!(MCPConnection, public_id: data.connection.id))
      end

      expected = Repo.get_by(MCPConnection, public_id: data.connection.id)
      send(worker, :release_catalog_result)
      assert_receive {:catalog_job_finished, _, _}, 3_000
      assert Repo.get_by(MCPConnection, public_id: data.connection.id) == expected
    end
  end

  for stop <- [:cancel, :timeout] do
    @tag job_stop: stop
    test "#{stop} closes held discovery and its supervised resources", data do
      live_queue!()

      if data.job_stop == :timeout,
        do: configure(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms, 300)

      server = start_supervised!({CheckHTTPFixture, owner: self(), hold: "tools/list"})
      protocol(server)
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:oban, :job, :exception],
          &CatalogDiscoveryProtocol.job_event/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
      job = Repo.one!(Oban.Job)
      assert_receive {:catalog_job_process, worker}, 3_000
      assert_receive {:check_http_held, "tools/list"}, 3_000
      [{_, session, _, _}] = DynamicSupervisor.which_children(Vxpipe.MCP.CheckSupervisor)
      pids = [worker, session | Enum.map(Supervisor.which_children(session), &elem(&1, 1))]
      monitors = Enum.map(pids, &{&1, Process.monitor(&1)})
      if data.job_stop == :cancel, do: assert(:ok == Oban.cancel_job(@oban, job.id))

      assert_receive {:check_http_closed, "tools/list", {:error, :closed}}, 2_000

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2_000)

      if data.job_stop == :timeout,
        do: assert_receive({:catalog_job_exception, job_id} when job_id == job.id, 2_000)

      saved = Repo.get_by!(MCPConnection, public_id: data.connection.id)
      assert saved.refreshed_at == nil
      assert saved.catalog == %{"tools" => data.connection.catalog}
      assert DynamicSupervisor.count_children(Vxpipe.MCP.CheckSupervisor).active == 0
    end
  end

  defp protocol(server, options \\ []) do
    configure(
      :vxpipe_calls,
      :mcp_catalog_protocol,
      {CatalogDiscoveryProtocol,
       Keyword.merge([owner: self(), endpoint: CheckHTTPFixture.endpoint(server)], options)}
    )
  end

  defp live_queue!(concurrency \\ 1) do
    stop_supervised!(@oban)

    start_supervised!(
      {Oban,
       name: @oban,
       repo: Repo,
       testing: :disabled,
       notifier: {Oban.Notifiers.PG, []},
       peer: {Oban.Peers.Isolated, [leader?: false]},
       queues: [mcp_catalog: concurrency]}
    )
  end

  defp observe_completion do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :stop],
        &CatalogDiscoveryProtocol.job_finished/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp configure(application, key, value) do
    previous = Application.fetch_env(application, key)
    Application.put_env(application, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(application, key, value)
        :error -> Application.delete_env(application, key)
      end
    end)
  end
end
