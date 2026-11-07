defmodule Vxpipe.Calls.MCPSavedPreflightTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPConnections
  alias Vxpipe.Calls.Test.{MCPOAuthReconnectFixture, MCPRepositoryFixture}
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    fixture = start_supervised!({MCPOAuthReconnectFixture, self()})

    entry = %{
      "directory_id" => "public",
      "integration_id" => "calendar",
      "revision" => 1,
      "endpoint" => "https://mcp.test/mcp",
      "name" => "Calendar",
      "authentication" => %{"type" => "oauth2", "registration" => "discover"}
    }

    MCPOAuthReconnectFixture.listing(fixture, entry)

    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    identity = %{
      origin: "https://console.test",
      revision: 2,
      redirect_uri: "https://console.test/oauth/mcp/callback"
    }

    authority = start_supervised!({Agent, fn -> {principal, identity} end})

    options = [
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_connection_repository: {MCPOAuthReconnectFixture, fixture},
      mcp_preflight: {__MODULE__, {self(), &Function.identity/1}},
      refresh_authority: fn -> {:ok, Agent.get(authority, &elem(&1, 0))} end,
      installation_identity: fn -> {:ok, Agent.get(authority, &elem(&1, 1))} end
    ]

    %{
      fixture: fixture,
      principal: principal,
      entry: entry,
      options: options,
      authority: authority
    }
  end

  def discover_saved({owner, transform}, tenant, input, origin, registration, entry) do
    send(owner, {:saved_discovery, tenant, input, origin, registration, entry})

    result = %{
      endpoint: entry["endpoint"],
      revision: input["revision"],
      listing: entry,
      outcome: :oauth,
      oauth_registration: %{method: "dcr", reusable: true}
    }

    {:ok, transform.(result)}
  end

  test "saved discovery binds trusted configuration and exposes no stored credentials", data do
    assert {:ok, result} = discover(data)
    assert result.connection_id == "connection"
    assert result.generation == 7
    assert result.revision == "draft"
    assert result.listing == data.entry

    assert_receive {:saved_discovery, @tenant,
                    %{"endpoint" => "https://mcp.test/mcp", "revision" => "draft"},
                    "https://console.test", registration, entry}

    assert entry == data.entry
    assert registration["client_id"] == "registered"
    refute Map.has_key?(registration, "access_token")
    refute Map.has_key?(registration, "refresh_token")
    refute inspect(result) =~ "registered"
    refute inspect(result) =~ "working-access"
    assert MCPOAuthReconnectFixture.snapshot(data.fixture).attempt == nil
  end

  test "legacy preflight adapters fail closed before reading saved registration", data do
    options =
      Keyword.put(
        data.options,
        :mcp_preflight,
        {Vxpipe.Calls.Test.MCPProbeFixture, {self(), {:ok, %{}}}}
      )

    assert {:error, :mcp_discovery_unavailable} = discover(%{data | options: options})
    refute_received :resolved
    refute_received {:mcp_preflight, _, _}
  end

  test "authority, tenant, generation and exact saved proposal are checked before secret resolution",
       data do
    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:error, :forbidden} = discover(%{data | principal: reader})

    assert {:error, :forbidden} =
             MCPConnections.preflight(data.principal, "BBBBBBBBBBBBBBBB", input(), data.options)

    assert {:error, :stale_mcp_connection} = discover(data, %{input() | "generation" => 6})

    for field <- ~w(endpoint listing credentials directory_entry initial_access_token auth_method) do
      assert {:error, :invalid_mcp_preflight} =
               discover(data, Map.put(input(), field, "override"))
    end

    assert {:error, :invalid_mcp_preflight} = discover(data, Map.delete(input(), "generation"))
    refute_received :resolved
    refute_received {:saved_discovery, _, _, _, _, _}
  end

  test "revoked and unreadable registrations never leak or reuse stored grants", data do
    MCPOAuthReconnectFixture.fail_resolve(data.fixture, :mcp_secret_unreadable)
    assert {:ok, _} = discover(data)
    assert_receive :resolved
    assert_receive {:saved_discovery, @tenant, _, _, %{}, _}
    MCPOAuthReconnectFixture.change(data.fixture, "revoked")
    assert {:ok, result} = discover(data, %{input() | "generation" => 8})
    assert result.generation == 8
    assert_receive {:saved_discovery, @tenant, _, _, %{}, _}
    refute_received :resolved
  end

  test "a protocol result for another draft or accepted snapshot is rejected", data do
    for transform <- [
          &Map.put(&1, :revision, "old"),
          &Map.put(&1, :endpoint, "https://other.test/mcp"),
          &put_in(&1, [:listing, "revision"], 2)
        ] do
      options = Keyword.put(data.options, :mcp_preflight, {__MODULE__, {self(), transform}})
      assert {:error, :mcp_discovery_unavailable} = discover(%{data | options: options})
    end
  end

  for change <- [:generation, :authority, :installation] do
    @change change
    test "held discovery rejects changed #{@change}", data do
      owner = self()

      transform = fn result ->
        send(owner, {:held, self()})
        receive do: (:continue -> result)
      end

      options = Keyword.put(data.options, :mcp_preflight, {__MODULE__, {self(), transform}})
      task = Task.async(fn -> discover(%{data | options: options}) end)
      assert_receive {:held, worker}

      expected =
        case @change do
          :generation ->
            MCPOAuthReconnectFixture.change(data.fixture, "connected")
            :stale_mcp_connection

          :authority ->
            Agent.update(data.authority, fn {principal, identity} ->
              {%{principal | grants: MapSet.new()}, identity}
            end)

            :forbidden

          :installation ->
            Agent.update(data.authority, fn {principal, identity} ->
              {principal, %{identity | revision: 3}}
            end)

            :mcp_installation_changed
        end

      send(worker, :continue)
      assert {:error, ^expected} = Task.await(task)
    end
  end

  defp input, do: %{"connection_id" => "connection", "generation" => 7, "revision" => "draft"}

  defp discover(data, input \\ input()),
    do: MCPConnections.preflight(data.principal, @tenant, input, data.options)
end
