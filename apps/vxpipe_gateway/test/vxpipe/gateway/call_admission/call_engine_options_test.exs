defmodule Vxpipe.Gateway.CallAdmission.CallEngineOptionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions

  test "MCP transport providers come only from trusted startup options" do
    provider = Vxpipe.CallEngine.TestRemoteMCPConnectionProvider

    call = %{
      tenant_key: "tenant",
      remote_mcp_connection_provider: :untrusted,
      plan: %{tenant_id: "tenant", participants: %{}, remote_mcp_connection_provider: :untrusted}
    }

    assert {:ok, defaults} = CallEngineOptions.build([], call)
    refute Keyword.has_key?(defaults, :remote_mcp_connection_provider)

    assert {:ok, runtime} =
             CallEngineOptions.build(
               [remote_mcp_connection_provider: provider, remote_mcp_protocol_client: :untrusted],
               call
             )

    assert Keyword.fetch!(runtime, :remote_mcp_connection_provider) == provider
    refute Keyword.has_key?(runtime, :remote_mcp_protocol_client)
  end

  test "packaged startup uses a fresh tenant MCP snapshot and rejects revoked records" do
    record = %{
      id: "connection",
      tenant_key: "tenant",
      generation: 1,
      status: "connected",
      auth_method: "bearer",
      endpoint: "https://mcp.example.test/mcp",
      catalog: [%{"name" => "lookup", "inputSchema" => %{"type" => "object"}}]
    }

    alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog
    {:ok, integration} = Vxpipe.Calls.SavedMCPCompilationCatalog.integration(record)

    {:ok, catalog} =
      IntegrationCatalog.new(tenants: %{"tenant" => %{"connection" => integration}})

    {:ok, remote} = IntegrationCatalog.resolve(catalog, "tenant", "connection", "lookup")

    call = %{
      tenant_key: "tenant",
      plan: %{
        tenant_id: "tenant",
        participants: %{
          "assistant" => %{tools: %{"lookup" => %{type: :mcp, remote: remote}}}
        }
      }
    }

    options = [
      mcp_connection_repository: {__MODULE__, record},
      mcp_runtime_resolver: {__MODULE__, self()}
    ]

    assert {:ok, runtime} = CallEngineOptions.build(options, call)
    assert {:ok, binding} = IntegrationCatalog.checkout(runtime[:mcp_catalog_store], remote)
    assert binding.client_config[:runtime_authentication].connection_id == "connection"

    assert {:error, :mcp_connection_unavailable} =
             CallEngineOptions.build(
               [mcp_connection_repository: {__MODULE__, %{record | status: "revoked"}}],
               call
             )

    assert {:error, :mcp_connection_unavailable} =
             CallEngineOptions.build(options, %{call | tenant_key: "other"})
  end

  def resolve(_owner, _tenant, _id, _generation), do: {:error, :unused}

  def resolve(record, _tenant, _id),
    do:
      {:ok,
       %Vxpipe.Calls.ResolvedMCPConnection{
         connection: record,
         secrets: %{"token" => "private-fixture-token"}
       }}

  test "passes trusted recording configuration to call startup" do
    recording = [
      enabled: true,
      targets: [:full_mix],
      writer: {TestWriter, [object_store: TestStore]},
      maximum_pull_frames: 4
    ]

    assert CallEngineOptions.build(recording: recording) == [
             archive: [enabled: false],
             recording: recording
           ]
  end

  test "managed startup scopes the real outgoing connector to its trusted call" do
    connector = Vxpipe.Gateway.Telephony.OutgoingLegConnector

    call = %{
      tenant_key: "tenant",
      id: "call",
      room_id: "room",
      plan: %{tenant_id: "tenant", participants: %{}}
    }

    options = [
      managed_cleanup: true,
      outbound_leg_connector: {connector, [media_admission: :media]}
    ]

    assert {:ok, runtime} = CallEngineOptions.build(options, call)
    assert {^connector, scoped} = Keyword.fetch!(runtime, :outbound_leg_connector)

    assert Keyword.fetch!(scoped, :cleanup_scope) == %{
             tenant_key: "tenant",
             call_id: "call",
             room_id: "room"
           }

    assert Keyword.fetch!(scoped, :media_admission) == :media
    assert Keyword.fetch!(Keyword.fetch!(scoped, :cleanup_options), :calls_options) == options
  end

  test "managed startup rejects a custom connector that cannot attest cleanup ownership" do
    assert {:error, :cleanup_connector_unavailable} =
             CallEngineOptions.build(
               [managed_cleanup: true, outbound_leg_connector: {CustomConnector, []}],
               %{
                 tenant_key: "tenant",
                 id: "call",
                 room_id: "room",
                 plan: %{tenant_id: "tenant", participants: %{}}
               }
             )
  end

  test "unmanaged calls preserve custom connectors without adding cleanup scope" do
    options = [outbound_leg_connector: {CustomConnector, [custom: true]}]

    assert {:ok, runtime} =
             CallEngineOptions.build(options, %{
               tenant_key: "tenant",
               id: "call",
               room_id: "room",
               plan: %{tenant_id: "tenant", participants: %{}}
             })

    assert Keyword.delete(runtime, :mcp_catalog_store) == CallEngineOptions.build(options)
  end
end
