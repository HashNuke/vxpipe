defmodule Vxpipe.Calls.MCPOAuthReconnectTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPOAuthAttempts
  alias Vxpipe.Calls.Test.{MCPOAuthReconnectFixture, MCPRepositoryFixture}
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    fixture = start_supervised!({MCPOAuthReconnectFixture, self()})

    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    options = [
      oauth_return_to: "/t/AAAAAAAAAAAAAAAA/services/calendar",
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_connection_repository: {MCPOAuthReconnectFixture, fixture},
      mcp_oauth_attempt_repository: {MCPOAuthReconnectFixture, fixture},
      mcp_oauth_preparation: {MCPOAuthReconnectFixture, fixture},
      mcp_oauth_completion: {MCPOAuthReconnectFixture, fixture},
      refresh_authority: fn -> {:ok, principal} end,
      installation_identity: fn ->
        {:ok,
         %{
           origin: "https://console.test",
           revision: 2,
           redirect_uri: "https://console.test/oauth/mcp/callback"
         }}
      end
    ]

    %{fixture: fixture, principal: principal, options: options}
  end

  defp input,
    do: %{
      "endpoint" => "https://mcp.test/mcp",
      "revision" => "draft",
      "auth_method" => "dcr",
      "generation" => 7
    }

  defp reconnect(data, input \\ input()),
    do: MCPOAuthAttempts.reconnect(data.principal, @tenant, "connection", input, data.options)

  test "reconnect preserves working credentials until a generation-checked callback succeeds",
       data do
    assert {:ok, handoff} = reconnect(data)
    assert handoff.connection_id == "connection"

    assert MCPOAuthReconnectFixture.snapshot(data.fixture).secrets["access_token"] ==
             "working-access"

    assert_receive {:issued, @tenant,
                    %{operation: "replace", generation: 7, connection_id: "connection"}}

    assert_receive {:prepared_reconnect, prepared_input, registration}
    refute Map.has_key?(prepared_input, "generation")
    assert registration["client_id"] == "registered"
    assert registration["scopes"] == ["tools:read"]
    refute Map.has_key?(registration, "access_token")
    refute Map.has_key?(registration, "refresh_token")

    assert {:ok, @tenant, record} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    assert record.id == "connection"
    assert record.return_to == "/t/AAAAAAAAAAAAAAAA/services/calendar"
    assert record.generation == 8
    stored = MCPOAuthReconnectFixture.snapshot(data.fixture)
    assert stored.secrets["access_token"] == "replacement-access"
    assert stored.connection.directory_id == "directory-calendar"
  end

  test "denied replacement leaves the old grant usable", data do
    assert {:ok, _} = reconnect(data)
    MCPOAuthReconnectFixture.completion(data.fixture, :deny)

    assert {:error, :oauth_consent_denied, context} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    assert context == %{
             tenant_key: @tenant,
             return_to: "/t/AAAAAAAAAAAAAAAA/services/calendar",
             attempt_id: "attempt"
           }

    stored = MCPOAuthReconnectFixture.snapshot(data.fixture)
    assert stored.connection.generation == 7
    assert stored.secrets["access_token"] == "working-access"
  end

  test "listed reconnect uses accepted snapshot and saved registration despite browser overrides",
       data do
    entry = listed_entry()
    MCPOAuthReconnectFixture.listing(data.fixture, entry)
    input = %{input() | "endpoint" => "https://other.test/mcp", "auth_method" => "none"}
    assert {:ok, _} = reconnect(data, input)
    assert_receive {:prepared_saved, canonical, registration, ^entry}
    assert canonical["endpoint"] == entry["endpoint"]
    assert registration["client_id"] == "registered"

    assert {:ok, @tenant, _} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    saved = MCPOAuthReconnectFixture.snapshot(data.fixture).connection
    assert saved.directory_entry == entry
    assert saved.directory_id == "directory/calendar"
    assert saved.server_name == "Accepted Calendar"
  end

  test "listed reconnect rejects a browser snapshot or new reference before secret resolution",
       data do
    MCPOAuthReconnectFixture.listing(data.fixture, listed_entry())

    for field <- ["directory_entry", "listing"] do
      assert {:error, :invalid_oauth_reconnect} = reconnect(data, Map.put(input(), field, %{}))
    end

    refute_received :resolved
    refute_received {:prepared_saved, _, _, _}
  end

  test "callback rejects a different accepted snapshot, directory identity or resource", data do
    entry = listed_entry()
    MCPOAuthReconnectFixture.listing(data.fixture, entry)
    assert {:ok, _} = reconnect(data)

    for tamper <- [
          %{directory_entry: nil},
          %{directory_id: "other/calendar"},
          %{directory_entry: Map.put(entry, "revision", 2)},
          %{endpoint: "https://other.test/mcp"},
          %{server_name: "Unaccepted name"}
        ] do
      MCPOAuthReconnectFixture.completion(data.fixture, {:tamper, tamper})

      assert {:error, :oauth_completion_failed, _} =
               MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)
    end

    assert MCPOAuthReconnectFixture.snapshot(data.fixture).connection.generation == 7
  end

  defp listed_entry do
    %{
      "directory_id" => "directory",
      "integration_id" => "calendar",
      "revision" => 1,
      "name" => "Accepted Calendar",
      "endpoint" => "https://mcp.test/mcp",
      "authentication" => %{"type" => "oauth2", "registration" => "discover"}
    }
  end

  test "protocol failure still rechecks authority before returning recovery context", data do
    assert {:ok, _} = reconnect(data)
    MCPOAuthReconnectFixture.completion(data.fixture, :deny)

    options =
      Keyword.put(data.options, :refresh_authority, fn ->
        receive do
          :completed -> {:ok, %{data.principal | grants: MapSet.new()}}
        after
          0 -> {:ok, data.principal}
        end
      end)

    assert {:error, :forbidden} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, options)

    assert MCPOAuthReconnectFixture.snapshot(data.fixture).secrets["access_token"] ==
             "working-access"
  end

  for status <- ["connected", "revoked"] do
    test "#{status} generation change during consent rejects before token redemption", data do
      assert {:ok, _} = reconnect(data)
      MCPOAuthReconnectFixture.change(data.fixture, unquote(status))

      assert {:error, _, %{tenant_key: @tenant}} =
               MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

      refute_received :completed

      assert MCPOAuthReconnectFixture.snapshot(data.fixture).secrets["access_token"] ==
               "newer-access"
    end
  end

  test "changing authentication during consent reports a stale connection", data do
    assert {:ok, _} = reconnect(data)
    MCPOAuthReconnectFixture.change(data.fixture, "connected", "bearer")

    assert {:error, :stale_mcp_connection, %{tenant_key: @tenant}} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    refute_received :completed
  end

  test "a concurrent edit during token exchange cannot be overwritten by the callback", data do
    assert {:ok, _} = reconnect(data)
    MCPOAuthReconnectFixture.completion(data.fixture, :change)

    assert {:error, :stale_mcp_connection, %{tenant_key: @tenant}} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    assert_receive :completed

    assert MCPOAuthReconnectFixture.snapshot(data.fixture).secrets["access_token"] ==
             "newer-access"
  end

  test "a writer in another tenant cannot reuse the saved registration", data do
    other = "BBBBBBBBBBBBBBBB"
    principal = %{data.principal | assigned_tenants: %{other => :read_write}}
    options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, principal} end)

    assert {:error, :mcp_connection_not_found} =
             MCPOAuthAttempts.reconnect(principal, other, "connection", input(), options)

    refute_received {:prepared_reconnect, _, _}
    assert MCPOAuthReconnectFixture.snapshot(data.fixture).attempt == nil
  end

  for status <- ["connected", "revoked"] do
    test "fresh OAuth can replace a #{status} static identity without resolving old secrets",
         data do
      MCPOAuthReconnectFixture.change(data.fixture, unquote(status), "bearer")

      assert {:ok, handoff} =
               reconnect(data, %{input() | "generation" => 8, "auth_method" => "cimd"})

      assert handoff.connection_id == "connection"
      assert_receive {:prepared_reconnect, _, registration}
      assert registration == %{}
      refute_received :resolved

      assert {:ok, @tenant, record} =
               MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

      assert record.generation == 9
      saved = MCPOAuthReconnectFixture.snapshot(data.fixture)
      assert saved.connection.namespace == "retained-namespace"
      assert saved.connection.directory_id == "directory-calendar"
      assert saved.connection.status == "connected"
      assert saved.secrets == %{"access_token" => "replacement-access"}
    end
  end

  test "unreadable saved DCR credentials fall back to fresh registration", data do
    MCPOAuthReconnectFixture.fail_resolve(data.fixture, :credential_key_unavailable)
    assert {:ok, _} = reconnect(data)
    assert_receive {:prepared_reconnect, _, registration}
    assert registration == %{}

    assert {:ok, @tenant, %{generation: 8}} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, data.options)

    assert MCPOAuthReconnectFixture.snapshot(data.fixture).secrets == %{
             "access_token" => "replacement-access"
           }
  end

  test "stale generation, changed endpoint and missing authority reject before remote work",
       data do
    assert {:error, :stale_mcp_connection} = reconnect(data, %{input() | "generation" => 6})

    assert {:error, :invalid_oauth_reconnect} =
             reconnect(data, %{input() | "endpoint" => "https://other.test/mcp"})

    assert {:error, :forbidden} =
             reconnect(%{data | principal: %{data.principal | grants: MapSet.new()}})

    refute_received {:prepared_reconnect, _, _}
    assert MCPOAuthReconnectFixture.snapshot(data.fixture).attempt == nil
  end
end
