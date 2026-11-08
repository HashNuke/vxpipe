defmodule Vxpipe.Persistence.MCP.CatalogRefreshStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{CatalogRefreshStore, ConnectionStore}
  alias Vxpipe.Persistence.Schema.MCPConnection

  @now ~U[2026-11-08 12:00:00.000000Z]
  @policy [expiry_seconds: 3_600, reschedule_after_seconds: 1_800, batch_size: 100]
  @oban Vxpipe.Persistence.TestCatalogJobs

  setup do
    start_supervised!({Oban, name: @oban, repo: Repo, testing: :manual})

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Catalog scheduling", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    %{
      tenant: tenant.key,
      context: [repo: Repo, oban: @oban, keyring: keyring, now: fn -> @now end]
    }
  end

  test "only stale connected catalogs outside the scheduling window are enqueued", data do
    unknown = connection!(data, nil, nil)
    boundary = connection!(data, ago(3_600), ago(1_800))
    recent = connection!(data, ago(3_601), ago(300))
    fresh = connection!(data, ago(3_599), nil)
    revoked = connection!(data, nil, nil)
    {:ok, _} = ConnectionStore.revoke(data.context, data.tenant, revoked.public_id, 1)
    context = Keyword.delete(data.context, :keyring)

    assert {:ok, 2} = CatalogRefreshStore.enqueue_due(context, @policy)
    jobs = Repo.all(from(j in Oban.Job, order_by: j.id))
    assert Enum.map(jobs, & &1.args["connection_id"]) == [unknown.public_id, boundary.public_id]

    for job <- jobs do
      assert Enum.sort(Map.keys(job.args)) ==
               ["connection_id", "generation", "scheduled_at", "tenant"]

      assert job.args["tenant"] == data.tenant
      assert job.args["generation"] == 1
      assert job.args["scheduled_at"] == DateTime.to_iso8601(@now)

      assert Repo.get!(
               MCPConnection,
               if(job.args["connection_id"] == unknown.public_id,
                 do: unknown.id,
                 else: boundary.id
               )
             ).refresh_scheduled_at == @now
    end

    assert Repo.get!(MCPConnection, recent.id).refresh_scheduled_at == ago(300)
    assert Repo.get!(MCPConnection, fresh.id).refresh_scheduled_at == nil
    assert {:ok, 0} = CatalogRefreshStore.enqueue_due(context, @policy)
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "incomplete jobs older than the window cannot starve later batches", data do
    records = for _ <- 1..5, do: connection!(data, nil, nil)
    policy = Keyword.put(@policy, :batch_size, 2)
    assert {:ok, 2} = CatalogRefreshStore.enqueue_due(data.context, policy)

    for record <- Enum.take(records, 2) do
      Repo.update!(
        Ecto.Changeset.change(Repo.get!(MCPConnection, record.id),
          refresh_scheduled_at: ago(1_801)
        )
      )
    end

    assert {:ok, 2} = CatalogRefreshStore.enqueue_due(data.context, policy)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, policy)
    assert Repo.aggregate(Oban.Job, :count) == 5
    assert {:ok, 0} = CatalogRefreshStore.enqueue_due(data.context, policy)

    for record <- Enum.take(records, 2) do
      assert Repo.get!(MCPConnection, record.id).refresh_scheduled_at == ago(1_801)
    end
  end

  test "terminal job history permits a new refresh after the suppression window", data do
    record = connection!(data, nil, nil)
    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    original = Repo.one!(Oban.Job)
    Repo.update!(Ecto.Changeset.change(original, state: "completed", completed_at: @now))

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(MCPConnection, record.id),
        refresh_scheduled_at: ago(1_800)
      )
    )

    assert {:ok, 1} = CatalogRefreshStore.enqueue_due(data.context, @policy)
    assert Repo.aggregate(Oban.Job, :count) == 2
    assert Repo.get!(MCPConnection, record.id).refresh_scheduled_at == @now
  end

  defp connection!(data, refreshed_at, scheduled_at) do
    endpoint = "https://catalog-#{System.unique_integer([:positive])}.example.test/mcp"

    {:ok, connection} =
      ConnectionStore.create(
        data.context,
        data.tenant,
        %{
          endpoint: endpoint,
          endpoint_identity: endpoint,
          server_name: "Catalog",
          auth_method: "bearer",
          catalog: []
        },
        %{"token" => "fixture"}
      )

    Repo.get_by!(MCPConnection, public_id: connection.id)
    |> Ecto.Changeset.change(refreshed_at: refreshed_at, refresh_scheduled_at: scheduled_at)
    |> Repo.update!()
  end

  defp ago(seconds), do: DateTime.add(@now, -seconds)
end
