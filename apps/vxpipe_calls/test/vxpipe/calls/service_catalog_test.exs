defmodule Vxpipe.Calls.ServiceCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.TestOperatorCredentialRepository
  alias Vxpipe.Identity.Principal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "lists only connected native and MCP services, without private connection metadata" do
    assert {:ok, %{services: services}} = Calls.list_services(actor(), @tenant, nil, options())

    assert Enum.map(services, & &1.service) == ["calendar", "telnyx"]

    assert %{
             kind: "provider",
             provider_id: "telnyx",
             source: :tenant,
             capabilities: ["telephony"]
           } =
             Enum.find(services, &(&1.service == "telnyx"))

    assert %{kind: "mcp", name: "Calendar", source: :tenant, capabilities: ["tools"]} =
             Enum.find(services, &(&1.service == "calendar"))

    encoded = JSON.encode!(services)
    refute encoded =~ "private-sentinel"
    refute encoded =~ "credential_id"
    refute encoded =~ "saved_fields"
    refute encoded =~ "endpoint"
    refute encoded =~ "deepgram"
    refute encoded =~ "morse"
  end

  test "platform grants control inherited services and filters apply to the visible inventory" do
    assert {:ok, %{services: services}} =
             Calls.list_services(actor(["platform_services.read"]), @tenant, nil, options())

    assert Enum.map(services, & &1.service) == ["calendar", "google", "telnyx"]

    assert {:ok, %{services: [%{service: "google", source: :platform}]}} =
             Calls.list_services(
               actor(["platform_services.read"]),
               @tenant,
               "speech_to_text",
               options()
             )

    assert {:ok, %{services: []}} =
             Calls.list_services(actor(), @tenant, "speech_to_text", options())

    assert {:ok, %{services: [%{service: "telnyx"}]}} =
             Calls.list_services(actor(), @tenant, "telephony", options())

    assert {:ok, %{services: [%{service: "calendar"}]}} =
             Calls.list_services(actor(), @tenant, "tools", options())

    assert {:error, :invalid_capability} =
             Calls.list_services(actor(), @tenant, "unknown", options())
  end

  test "checks tenant and delegation before reading either inventory" do
    delegated = %{
      actor(["platform_services.read"])
      | delegation: %{assigned_tenants: %{}, all_tenant_actions: MapSet.new()}
    }

    for {principal, tenant} <- [
          {actor(), @other},
          {delegated, @tenant},
          {%{actor() | grants: MapSet.new()}, @tenant}
        ] do
      assert {:error, :forbidden} = Calls.list_services(principal, tenant, nil, options())
      refute_received {:operator_bindings_requested, _}
      refute_received {:mcps_requested, _}
    end
  end

  test "rejects foreign inventory and propagates outages rather than inventing an empty list" do
    assert {:error, :service_directory_unavailable} =
             Calls.list_services(actor(), @tenant, nil, options(@other))

    opts = Keyword.put(options(), :mcp_connection_repository, {__MODULE__, :unavailable})
    assert {:error, :mcp_catalog_unavailable} = Calls.list_services(actor(), @tenant, nil, opts)
  end

  def list(:unavailable, _tenant), do: {:error, :unavailable}

  def list(owner, tenant) do
    send(owner, {:mcps_requested, tenant})

    {:ok,
     [
       %{
         id: "calendar",
         tenant_key: tenant,
         generation: 1,
         status: "connected",
         catalog: [],
         server_name: "Calendar",
         endpoint: "https://private-sentinel.example/mcp",
         secrets: "private-sentinel"
       }
     ]}
  end

  defp actor(extra \\ []) do
    %Principal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :member,
      grants: MapSet.new(["call_specs.read" | extra]),
      assigned_tenants: %{@tenant => :read},
      all_tenant_actions: MapSet.new()
    }
  end

  defp options(tenant \\ @tenant) do
    directory = %{
      tenant: %{key: tenant, name: "Example"},
      bindings: [
        binding("telnyx", :tenant, :connected),
        binding("google", :platform, :connected),
        binding("deepgram", :tenant, :invalid)
      ]
    }

    [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, directory}),
      mcp_connection_repository: {__MODULE__, self()}
    ]
  end

  defp binding(provider, source, status),
    do: %{
      provider: provider,
      name: provider,
      source: source,
      status: status,
      credential_id: "private-sentinel",
      platform_available: true,
      saved_fields: ["api_key"],
      last_validated_at: nil,
      payload: %{api_key: "private-sentinel"}
    }
end
