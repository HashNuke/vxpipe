defmodule Vxpipe.Console.OutboundMCPOAuthRenewalTest do
  use Vxpipe.Console.Test.OutboundMCPOAuthCase, async: false
  alias Vxpipe.Calls.{MCPOAuthRefresh, MCPRuntimeCredentials}

  setup data do
    options =
      Keyword.put(
        data.options,
        :mcp_oauth_refresh,
        {Vxpipe.Calls.MCPOAuthProtocol, data.protocol}
      )

    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(calls, options))
    %{options: options}
  end

  for method <- ~w(client_secret_basic client_secret_post private_key_jwt) do
    @tag mode: "own_client", client_auth_method: method, grant: "client_credentials"
    test "machine #{method} connects and renews through HTTP and storage without browser consent",
         data do
      credentials = register_own(data, 0)

      input = %{
        "endpoint" => OutboundMCPOAuthServer.resource(),
        "revision" => "draft",
        "auth_method" => "own_client",
        "credentials" => credentials
      }

      discovery = request(data, :post, "/mcp-discovery", Map.take(input, ~w(endpoint revision)))

      assert json_response(discovery, 200)["discovery"]["supported_grants"] == [
               "client_credentials"
             ]

      assert count(data, {"POST", "/token"}) == 0

      created = request(data, :post, "/mcp-connections", input) |> json_response(201)
      id = created["connection"]["id"]
      first = resolve(data, id)
      assert first.secrets["grant_type"] == "client_credentials"
      assert first.connection.auth_method == "oauth"

      for key <- ~w(refresh_token code_verifier redirect_uri),
          do: refute(Map.has_key?(first.secrets, key))

      assert Repo.aggregate(MCPOAuthAttempt, :count) == 0

      {:ok, expiry, _} = DateTime.from_iso8601(first.secrets["expires_at"])
      options = Keyword.put(data.options, :now, fn -> DateTime.add(expiry, -10) end)
      assert {:ok, runtime} = MCPRuntimeCredentials.resolve(data.tenant, id, 1, options)
      refreshed = resolve(data, id)
      assert_tools_refresh(data, id, refreshed.secrets)
      rediscovered = resolve(data, id)
      assert rediscovered.secrets == refreshed.secrets

      assert Map.delete(rediscovered.connection, :refreshed_at) ==
               Map.delete(refreshed.connection, :refreshed_at)

      assert DateTime.compare(
               rediscovered.connection.refreshed_at,
               refreshed.connection.refreshed_at
             ) == :gt

      assert runtime.secrets == %{
               "access_token" => refreshed.secrets["access_token"],
               "headers" => credentials["headers"]
             }

      refute refreshed.secrets["access_token"] == first.secrets["access_token"]
      assert refreshed.secrets["grant_revision"] == 2
      refute Map.has_key?(refreshed.secrets, "refresh_token")

      replacement_credentials = register_own(data, 1)

      replacement =
        input |> Map.put("credentials", replacement_credentials) |> Map.put("generation", 1)

      OutboundMCPOAuthServer.configure(data.peer, %{mcp_fail: true})
      assert json_response(request(data, :patch, "/mcp-connections/#{id}", replacement), 503)
      assert resolve(data, id) == rediscovered
      OutboundMCPOAuthServer.configure(data.peer, %{mcp_fail: false})
      assert json_response(request(data, :patch, "/mcp-connections/#{id}", replacement), 200)
      current = resolve(data, id)
      assert current.connection.generation == 2
      assert current.secrets["client_secret"] == replacement_credentials["client_secret"]
      assert current.secrets["private_key"] == replacement_credentials["private_key"]
      assert count(data, {"POST", "/token"}) == 4
      assert count(data, {"POST", "/register"}) == 0
      assert count(data, {"GET", "/authorize"}) == 0
      assert Repo.aggregate(MCPOAuthAttempt, :count) == 0

      assert json_response(
               request(data, :delete, "/mcp-connections/#{id}", %{"generation" => 2}),
               200
             )

      assert {:error, :mcp_connection_unavailable} =
               MCPRuntimeCredentials.resolve(data.tenant, id, 2, data.options)

      assert count(data, {"POST", "/token"}) == 4
      assert is_nil(Repo.get_by!(MCPConnection, public_id: id).encrypted_payload)
    end
  end

  for mode <- ["cimd", "dcr"] do
    @tag mode: mode
    test "#{mode} rotates its saved grant and refreshes tools without changing identity", data do
      handoff = start(data)
      assert_connected(data, authorize(data, handoff))
      id = handoff["connection_id"]
      first = resolve(data, id)
      assert :ok = MCPOAuthRefresh.refresh(data.tenant, id, 1, 1, data.options)
      refreshed = resolve(data, id)
      assert_tools_refresh(data, id, refreshed.secrets)
      refute refreshed.secrets["access_token"] == first.secrets["access_token"]
      refute refreshed.secrets["refresh_token"] == first.secrets["refresh_token"]
      assert refreshed.secrets["client_id"] == first.secrets["client_id"]
      assert refreshed.connection.generation == 1
      assert count(data, "tools/call") == 0
    end
  end

  for method <- ~w(none client_secret_basic client_secret_post private_key_jwt) do
    @tag mode: "own_client", client_auth_method: method
    test "registered #{method} grant rotates and refreshes tools with its saved private configuration",
         data do
      credentials = register_own(data, 0)
      handoff = start(data, nil, credentials)
      assert_connected(data, authorize(data, handoff))
      id = handoff["connection_id"]
      first = resolve(data, id)
      assert :ok = MCPOAuthRefresh.refresh(data.tenant, id, 1, 1, data.options)
      refreshed = resolve(data, id)
      assert_tools_refresh(data, id, refreshed.secrets)
      refute refreshed.secrets["access_token"] == first.secrets["access_token"]
      assert refreshed.secrets["headers"] == credentials["headers"]
      assert count(data, {"POST", "/token"}) == 2

      if data.client_auth_method == "private_key_jwt",
        do: assert(Agent.get(data.peer, &MapSet.size(&1.assertion_ids)) == 2)
    end
  end

  defp assert_tools_refresh(data, id, secrets) do
    response =
      request(data, :patch, "/mcp-connections/#{id}", %{
        "generation" => 1,
        "refresh_tools" => true
      })

    assert json_response(response, 200)["connection"]["generation"] == 1
    assert resolve(data, id).secrets == secrets
  end
end
