defmodule Vxpipe.Persistence.MCP.CatalogFreshnessTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.MCPConnection

  @now ~U[2026-11-08 12:00:00.000000Z]

  setup do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Catalog freshness", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    %{
      tenant: tenant.key,
      context: [repo: Repo, keyring: keyring, now: fn -> @now end],
      attributes: %{
        endpoint: "https://catalog.example.test/mcp",
        endpoint_identity: "https://catalog.example.test/mcp",
        server_name: "Catalog",
        auth_method: "bearer",
        catalog: []
      }
    }
  end

  test "successful initial discovery records freshness without pretending a job was scheduled",
       data do
    assert {:ok, connection} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{
               "token" => "fixture"
             })

    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    assert Map.get(record, :refreshed_at) == @now
    assert Map.get(connection, :refreshed_at) == @now
    assert Map.get(record, :refresh_scheduled_at) == nil
  end

  test "OAuth completion records the discovered catalog freshness", data do
    assert {:ok, connection} =
             ConnectionStore.create_oauth(
               data.context,
               data.tenant,
               Ecto.UUID.generate(),
               %{data.attributes | auth_method: "oauth"},
               %{"access_token" => "fixture"}
             )

    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    assert Map.get(record, :refreshed_at) == @now
    assert record.catalog == %{"tools" => []}
  end

  test "a successful empty refresh advances freshness and rejects a competing stale result",
       data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "fixture"})

    guard = freshness(connection)
    attributes = %{server_name: "Current catalog", catalog: []}

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               connection.id,
               1,
               guard,
               attributes
             )

    assert refreshed.refreshed_at == DateTime.add(@now, 1, :microsecond)
    assert refreshed.refresh_scheduled_at == nil

    assert {:error, :stale_mcp_catalog} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               connection.id,
               1,
               guard,
               %{attributes | server_name: "Stale result"}
             )

    assert {:ok, current} = ConnectionStore.get(data.context, data.tenant, connection.id)
    assert current.server_name == "Current catalog"
    assert current.refreshed_at == refreshed.refreshed_at
  end

  test "publication advances beyond prior freshness even if the clock moves backwards", data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "fixture"})

    earlier = Keyword.put(data.context, :now, fn -> DateTime.add(@now, -60) end)

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               earlier,
               data.tenant,
               connection.id,
               1,
               freshness(connection),
               %{server_name: "Catalog", catalog: []}
             )

    assert refreshed.refreshed_at == DateTime.add(@now, 1, :microsecond)
  end

  test "unknown-age catalogs accept one NULL-safe publication and reject its duplicate", data do
    {:ok, connection} = ConnectionStore.create(data.context, data.tenant, data.attributes, %{})
    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    Repo.update!(Ecto.Changeset.change(record, refreshed_at: nil))
    guard = %{refreshed_at: nil, refresh_scheduled_at: nil}
    attributes = %{server_name: "Current", catalog: []}

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               connection.id,
               1,
               guard,
               attributes
             )

    assert refreshed.refreshed_at == @now

    assert {:error, :stale_mcp_catalog} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               connection.id,
               1,
               guard,
               attributes
             )
  end

  test "reencryption does not change catalog freshness or scheduling", data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "fixture"})

    old_keys = Keyword.fetch!(data.context, :keyring)

    {:ok, keys} =
      CredentialKeyring.new(
        "new",
        Map.put(old_keys.keys, "new", :crypto.strong_rand_bytes(32))
      )

    context =
      data.context
      |> Keyword.put(:keyring, keys)
      |> Keyword.put(:now, fn -> DateTime.add(@now, 60) end)

    assert {:ok, %{processed: 1}} = ConnectionStore.reencrypt(context, 10)
    record = Repo.get_by!(MCPConnection, public_id: connection.id)
    assert record.refreshed_at == @now
    assert record.refresh_scheduled_at == nil
  end

  defp freshness(connection),
    do: %{
      refreshed_at: Map.get(connection, :refreshed_at),
      refresh_scheduled_at: Map.get(connection, :refresh_scheduled_at)
    }
end
