defmodule Vxpipe.Console.IntegrationsDirectory.InventoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.Inventory
  alias Vxpipe.Console.Test.{FakeUserIdentity, OperatorCredentialRepository}

  @tenant "AAAAAAAAAAAAAAAA"

  test "joins effective local status while sending only public parameters" do
    owner = self()

    fetcher = fn resource, params ->
      send(owner, {:public_request, resource, params})
      {:ok, %{body: %{"items" => [provider_row()]}, etag: nil}}
    end

    assert {:ok, result} =
             Inventory.list(
               FakeUserIdentity.principal(),
               @tenant,
               %{"q" => "google"},
               options(fetcher)
             )

    assert_receive {:public_request, :integrations,
                    %{"q" => "google", "scope" => "tenant", "limit" => 20}}

    assert [%{"connections" => [%{status: :invalid, can_edit: true}]}] = result.page["items"]
    refute inspect(result) =~ "private-payload"
  end

  test "unknown local status prevents fetching and never becomes an enabled Connect" do
    options = options(fn _, _ -> flunk("must not fetch directory with unknown local state") end)

    calls = [
      provider_credential_repository:
        {OperatorCredentialRepository, {self(), {:error, :unavailable}}}
    ]

    assert {:error, :connection_status_unavailable} =
             Inventory.list(
               FakeUserIdentity.principal(),
               @tenant,
               %{},
               Keyword.put(options, :calls_options, calls)
             )
  end

  test "directory outages offer installed credential adapters only, without remote pagination" do
    assert {:ok, result} =
             Inventory.list(
               FakeUserIdentity.principal(),
               @tenant,
               %{},
               options(fn _, _ -> {:error, :unavailable} end)
             )

    assert result.directory_status == :unavailable
    assert result.page == nil
    ids = Enum.map(result.fallback_items, & &1["connection"]["provider_id"])
    assert "google" in ids
    assert "twilio" in ids
    refute "morse" in ids
    assert Enum.all?(result.fallback_items, &(&1["kind"] == "provider"))
  end

  test "Connected is local and preserves invalid overrides for management" do
    assert {:ok, result} =
             Inventory.list(
               FakeUserIdentity.principal(),
               @tenant,
               %{"category" => "connected"},
               options(fn _, _ -> flunk("Connected must remain local") end)
             )

    assert result.directory_status == :local

    assert [
             %{
               "connection" => %{"provider_id" => "google"},
               "connections" => [%{status: :invalid}]
             }
           ] = result.local_items
  end

  test "denied tenant access does not reach the public directory" do
    principal = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    assert {:error, :forbidden} =
             Inventory.list(
               principal,
               @tenant,
               %{},
               options(fn _, _ -> flunk("unauthorized fetch") end)
             )
  end

  test "saved MCPs stay local during outage and join directory identity", _context do
    saved = %{
      id: "mcp-id",
      tenant_key: @tenant,
      endpoint: "https://mcp.example.test/mcp",
      server_name: "Tools",
      auth_method: "bearer",
      generation: 1,
      status: "connected",
      directory_id: "listed-mcp",
      tool_count: 0
    }

    opts =
      options(fn _, _ -> flunk("local inventory must not fetch") end)
      |> Keyword.put(:mcp_loader, fn _, _, _ -> {:ok, [saved]} end)

    assert {:ok, result} =
             Inventory.list(
               FakeUserIdentity.principal(),
               @tenant,
               %{"category" => "connected"},
               opts
             )

    assert Enum.any?(result.local_items, &(&1["kind"] == "mcp" and &1["name"] == "Tools"))
    assert [%{id: "mcp-id", can_edit: true}] = result.mcp_connections

    row = %{
      "id" => "listed-mcp",
      "kind" => "mcp",
      "connection" => %{"endpoint" => saved.endpoint}
    }

    opts = Keyword.put(opts, :fetcher, fn _, _ -> {:ok, %{body: %{"items" => [row]}}} end)
    assert {:ok, result} = Inventory.list(FakeUserIdentity.principal(), @tenant, %{}, opts)

    assert [%{"mcp_connections" => [%{id: "mcp-id"}], "can_connect" => false}] =
             result.page["items"]

    opts = Keyword.put(opts, :fetcher, fn _, _ -> {:error, :unavailable} end)
    assert {:ok, result} = Inventory.list(FakeUserIdentity.principal(), @tenant, %{}, opts)
    assert [%{id: "mcp-id"}] = result.mcp_connections
  end

  test "unknown MCP status fails closed" do
    opts =
      options(fn _, _ -> flunk("unknown local status must not fetch") end)
      |> Keyword.put(:mcp_loader, fn _, _, _ -> {:error, :unavailable} end)

    assert {:error, :connection_status_unavailable} =
             Inventory.list(FakeUserIdentity.principal(), @tenant, %{}, opts)
  end

  test "native credential and MCP mutations use their separate permission grants" do
    for action <- ["tenant_api_keys.write", "tenant_services.write"] do
      actions = MapSet.new(["tenant_services.read", action])

      principal = %{
        FakeUserIdentity.principal()
        | account_kind: :member,
          grants: actions,
          all_tenant_actions: actions
      }

      saved = %{id: "saved", endpoint: "https://mcp.example.test/mcp", server_name: "Tools"}

      options =
        options(fn _, _ ->
          {:ok,
           %{
             body: %{
               "items" => [
                 provider_row(),
                 %{"kind" => "provider", "connection" => %{"provider_id" => "openai"}}
               ]
             }
           }}
        end)
        |> Keyword.put(:mcp_loader, fn _, _, _ -> {:ok, [saved]} end)

      assert {:ok, result} = Inventory.list(principal, @tenant, %{}, options)

      assert [%{"connections" => [%{can_edit: native_edit}]}, %{"can_connect" => native_connect}] =
               result.page["items"]

      assert native_edit == (action == "tenant_api_keys.write")
      assert native_connect == (action == "tenant_api_keys.write")
      assert [%{can_edit: mcp_edit}] = result.mcp_connections
      assert mcp_edit == (action == "tenant_services.write")
    end
  end

  test "native capability labels come from installed adapters on local, remote and fallback rows" do
    remote = Map.put(provider_row(), "capabilities", ["telephony", "download_code"])

    for {params, fetcher} <- [
          {%{"category" => "connected"}, fn _, _ -> flunk("connected is local") end},
          {%{}, fn _, _ -> {:ok, %{body: %{"items" => [remote]}}} end},
          {%{}, fn _, _ -> {:error, :unavailable} end}
        ] do
      assert {:ok, result} =
               Inventory.list(FakeUserIdentity.principal(), @tenant, params, options(fetcher))

      rows =
        case result.directory_status do
          :available -> result.page["items"]
          :local -> result.local_items
          :unavailable -> result.fallback_items
        end

      google = Enum.find(rows, &(&1["connection"]["provider_id"] == "google"))
      assert Map.fetch!(google, "capabilities") == [:llm, :sts, :stt, :tts]
    end
  end

  defp options(fetcher) do
    binding = %{
      provider: "google",
      name: "google",
      source: :tenant,
      status: :invalid,
      credential_id: "credential-id",
      platform_available: true,
      saved_fields: ["api_key"],
      last_validated_at: nil,
      payload: "private-payload"
    }

    [
      fetcher: fetcher,
      mcp_loader: fn _, _, _ -> {:ok, []} end,
      calls_options: [
        provider_credential_repository:
          {OperatorCredentialRepository,
           {self(), {:ok, %{tenant: %{key: @tenant, name: "Tenant"}, bindings: [binding]}}}}
      ]
    ]
  end

  defp provider_row, do: %{"kind" => "provider", "connection" => %{"provider_id" => "google"}}
end
