defmodule Vxpipe.Calls.MCPCatalogRefreshTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPCatalogRefresh, ResolvedMCPConnection}
  alias Vxpipe.Calls.Test.MCPCatalogRefreshFixture

  @scheduled ~U[2026-11-08 12:00:00.000000Z]
  @refreshed ~U[2026-11-08 10:00:00.000000Z]

  setup do
    saved = %ResolvedMCPConnection{
      connection: %{
        tenant_key: "tenant",
        id: "connection",
        generation: 1,
        status: "connected",
        endpoint: "https://catalog.example.test/mcp",
        auth_method: "bearer",
        refreshed_at: @refreshed,
        refresh_scheduled_at: @scheduled
      },
      secrets: %{"token" => "synthetic-private"}
    }

    port = {MCPCatalogRefreshFixture, {self(), saved}}
    observer = self()

    %{
      args: %{
        "tenant" => "tenant",
        "connection_id" => "connection",
        "generation" => 1,
        "scheduled_at" => DateTime.to_iso8601(@scheduled)
      },
      options: [
        mcp_catalog_refresh_repository: port,
        mcp_connection_repository: port,
        connection_check: fn tenant, configuration ->
          send(observer, {:catalog_discovery, tenant, configuration.secrets})
          {:ok, %{server_name: "Current", catalog: []}}
        end
      ]
    }
  end

  test "headless refresh resolves current credentials and publishes with its original guard",
       data do
    assert :ok = MCPCatalogRefresh.refresh(data.args, data.options)
    assert_receive {:catalog_candidate, args, _policy}
    assert args == data.args
    assert_receive {:catalog_credentials, "tenant", "connection"}
    assert_receive {:catalog_discovery, "tenant", %{"token" => "synthetic-private"}}

    assert_receive {:catalog_publish, "tenant", "connection", 1,
                    %{refreshed_at: @refreshed, refresh_scheduled_at: @scheduled},
                    %{server_name: "Current", catalog: []}}
  end

  test "obsolete work stops before credential resolution and protocol work", data do
    options =
      Keyword.put(
        data.options,
        :mcp_catalog_refresh_repository,
        {MCPCatalogRefreshFixture, {self(), nil}}
      )

    assert :ok = MCPCatalogRefresh.refresh(data.args, options)
    refute_received {:catalog_credentials, _, _}
    refute_received {:catalog_discovery, _, _}
    refute_received {:catalog_publish, _, _, _, _, _}
  end

  test "a host protocol port receives the bounded discovery request", data do
    options =
      data.options
      |> Keyword.delete(:connection_check)
      |> Keyword.put(:mcp_catalog_protocol, {MCPCatalogRefreshFixture, [owner: self()]})

    assert :ok = MCPCatalogRefresh.refresh(data.args, options)
    assert_receive {:catalog_protocol, "tenant", %{"token" => "synthetic-private"}, 10_000}
  end

  test "failed discovery keeps the last saved catalog", data do
    options =
      Keyword.put(data.options, :connection_check, fn _, _ -> {:error, :mcp_connection_failed} end)

    assert {:error, :mcp_connection_failed} = MCPCatalogRefresh.refresh(data.args, options)
    refute_received {:catalog_publish, _, _, _, _, _}
  end

  test "sweep policy comes from bounded application options", data do
    policy = [expiry_seconds: 120, reschedule_after_seconds: 1_800, batch_size: 10]
    options = Keyword.put(data.options, :catalog_refresh_policy, policy)
    assert {:ok, 2} = MCPCatalogRefresh.sweep(options)
    assert_receive {:catalog_sweep, ^policy}

    for key <- [:expiry_seconds, :reschedule_after_seconds, :batch_size] do
      assert {:error, :invalid_catalog_refresh_policy} =
               MCPCatalogRefresh.sweep(
                 Keyword.put(options, :catalog_refresh_policy, Keyword.put(policy, key, 0))
               )
    end
  end

  test "unexpected or malformed job arguments are rejected before loading secrets", data do
    for args <- [
          Map.put(data.args, "token", "private"),
          Map.put(data.args, "generation", 0),
          Map.put(data.args, "scheduled_at", "bad-date")
        ] do
      assert {:error, :invalid_catalog_refresh_job} =
               MCPCatalogRefresh.refresh(args, data.options)
    end

    refute_received {:catalog_candidate, _, _}
    refute_received {:catalog_credentials, _, _}
  end
end
