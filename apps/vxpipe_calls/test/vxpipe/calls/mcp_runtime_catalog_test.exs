defmodule Vxpipe.Calls.MCPRuntimeCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog
  alias Vxpipe.Calls.{MCPRuntimeCatalog, ResolvedMCPConnection, SavedMCPCompilationCatalog}
  alias Vxpipe.Calls.Test.{MCPCatalogFixture, MCPRuntimeFixture}

  setup do
    record = %{
      id: "connection",
      tenant_key: "tenant",
      generation: 2,
      status: "connected",
      endpoint: "https://mcp.example.test/mcp",
      auth_method: "bearer",
      catalog: [%{"name" => "lookup", "inputSchema" => %{"type" => "object"}}]
    }

    assert {:ok, catalog} =
             SavedMCPCompilationCatalog.build("tenant",
               mcp_connection_repository: {MCPCatalogFixture, {:ok, [record]}}
             )

    assert {:ok, remote} = IntegrationCatalog.resolve(catalog, "tenant", "connection", "lookup")

    saved = %ResolvedMCPConnection{
      connection: record,
      secrets: %{"token" => "private-runtime-token"}
    }

    agent = start_supervised!({Agent, fn -> saved end})
    repository = {MCPRuntimeFixture, {self(), agent}}

    options = [
      mcp_connection_repository: repository,
      mcp_runtime_resolver: {MCPRuntimeFixture, {self(), agent}}
    ]

    plan = %{
      tenant_id: "tenant",
      participants: %{
        "assistant" => %{
          tools: %{
            "lookup" => %{type: :mcp, remote: remote},
            "again" => %{type: :mcp, remote: remote}
          }
        }
      }
    }

    %{plan: plan, remote: remote, agent: agent, options: options}
  end

  test "resolves selected static credentials once and keeps them private", data do
    assert {:ok, catalog} = MCPRuntimeCatalog.build(data.plan, data.options)
    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, data.remote)

    assert integration.client_config[:authentication] == :none

    assert integration.client_config[:endpoint] == "https://mcp.example.test/mcp"
    refute inspect(catalog) =~ "private-runtime-token"
    refute :erlang.term_to_binary(catalog) =~ "private-runtime-token"
    assert_received :resolved
    refute_received :resolved
  end

  test "native-only plans need no MCP repository" do
    assert {:ok, catalog} = MCPRuntimeCatalog.build(%{tenant_id: "tenant", participants: %{}}, [])
    assert IntegrationCatalog.tools(catalog, "tenant") == []
  end

  test "operation-level repository overrides require a nonsecret runtime resolver", data do
    assert {:error, :mcp_connection_unavailable} =
             MCPRuntimeCatalog.build(
               data.plan,
               Keyword.delete(data.options, :mcp_runtime_resolver)
             )

    for context <- [[keyring: "synthetic-key"], fn -> "synthetic-key" end, "synthetic-key"] do
      assert {:error, :mcp_connection_unavailable} =
               MCPRuntimeCatalog.build(
                 data.plan,
                 Keyword.put(data.options, :mcp_runtime_resolver, {MCPRuntimeFixture, context})
               )
    end
  end

  test "startup binding rechecks saved generation and revocation before submission", data do
    assert {:ok, catalog} = MCPRuntimeCatalog.build(data.plan, data.options)
    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, data.remote)
    assert {:ok, client_options} = Vxpipe.MCP.ClientOptions.build(integration.client_config)
    assert {Vxpipe.MCP.RuntimeAuthProvider, state} = client_options[:auth_provider]
    assert {:ok, nil, ^state} = Vxpipe.MCP.RuntimeAuthProvider.get_token(state)

    Agent.update(data.agent, fn saved ->
      %{saved | connection: %{saved.connection | status: "revoked"}}
    end)

    assert catch_exit(Vxpipe.MCP.RuntimeAuthProvider.get_token(state)) ==
             :mcp_credentials_unavailable
  end

  test "rejects foreign scopes before any credential lookup", data do
    assert {:error, :mcp_connection_unavailable} =
             MCPRuntimeCatalog.build(%{data.plan | tenant_id: "other"}, data.options)

    refute_received :resolved
  end

  test "OAuth binding resolves tokens at submission without storing them in client configuration",
       data do
    Agent.update(data.agent, fn saved ->
      %{
        saved
        | connection: %{saved.connection | auth_method: "oauth"},
          secrets: %{"access_token" => "expired", "expires_at" => "2020-01-01T00:00:00Z"}
      }
    end)

    options = data.options

    assert {:ok, catalog} = MCPRuntimeCatalog.build(data.plan, options)
    refute_received :refreshed
    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, data.remote)
    assert {:ok, client_options} = Vxpipe.MCP.ClientOptions.build(integration.client_config)
    assert client_options[:headers] == []
    assert {Vxpipe.MCP.RuntimeAuthProvider, state} = client_options[:auth_provider]
    assert {:ok, "new", ^state} = Vxpipe.MCP.RuntimeAuthProvider.get_token(state)
    assert_receive :refreshed
  end

  test "rejects changed configuration and schemas at startup", data do
    for update <- [
          fn record -> %{record | generation: 3} end,
          fn record -> %{record | catalog: []} end
        ] do
      original = Agent.get(data.agent, & &1)
      Agent.update(data.agent, &%{&1 | connection: update.(&1.connection)})

      assert {:error, :mcp_connection_unavailable} =
               MCPRuntimeCatalog.build(data.plan, data.options)

      Agent.update(data.agent, fn _ -> original end)
    end
  end

  test "OAuth startup keeps saved MCP headers but excludes token-request credentials", data do
    Agent.update(data.agent, fn saved ->
      %{
        saved
        | connection: %{saved.connection | auth_method: "oauth"},
          secrets: %{
            "access_token" => "private-access-token",
            "private_key" => "private-signing-key",
            "client_secret" => "private-client-secret",
            "headers" => [%{"name" => "X-Workspace", "value" => "workspace-secret"}]
          }
      }
    end)

    assert {:ok, catalog} = MCPRuntimeCatalog.build(data.plan, data.options)
    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, data.remote)
    assert {:ok, client_options} = Vxpipe.MCP.ClientOptions.build(integration.client_config)
    assert client_options[:headers] == []

    for secret <- ~w(private-access-token private-signing-key private-client-secret) do
      refute inspect(integration.client_config) =~ secret
    end

    refute inspect(catalog) =~ "workspace-secret"
    refute :erlang.term_to_binary(catalog) =~ "workspace-secret"
  end

  test "OAuth startup rejects headers that could replace the runtime bearer", data do
    for header <- ["Authorization", "aUtHoRiZaTiOn"] do
      Agent.update(data.agent, fn saved ->
        %{
          saved
          | connection: %{saved.connection | auth_method: "oauth"},
            secrets: %{"headers" => [%{"name" => header, "value" => "Bearer stale"}]}
        }
      end)

      assert {:error, :mcp_connection_unavailable} =
               MCPRuntimeCatalog.build(data.plan, data.options)
    end
  end
end
