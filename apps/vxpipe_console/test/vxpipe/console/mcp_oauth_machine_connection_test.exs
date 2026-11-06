defmodule Vxpipe.Console.MCPOAuthMachineConnectionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPConnectionProbe
  alias Vxpipe.MCP.PreflightRunner

  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"

  setup do
    owner = self()
    tasks = start_supervised!({Task.Supervisor, name: nil})
    runner = start_supervised!({PreflightRunner, name: nil, task_supervisor: tasks, interval: 0})

    input = %{
      "endpoint" => @endpoint,
      "revision" => "draft",
      "auth_method" => "own_client",
      "credentials" => %{
        "grant_type" => "client_credentials",
        "client_id" => "registered",
        "client_auth_method" => "client_secret_post",
        "client_secret" => "private-secret",
        "headers" => [%{"name" => "X-Workspace", "value" => "private-workspace"}],
        "token_parameters" => [%{"name" => "organization", "value" => "calendar"}]
      }
    }

    metadata = %{
      "issuer" => @issuer,
      "token_endpoint" => @issuer <> "/token",
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => ["client_secret_post"]
    }

    options = [
      preflight_runner: runner,
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        case {uri.host, uri.path} do
          {_, "/mcp"} ->
            response(401, %{})

          {"mcp.example.test", _} ->
            response(200, %{
              "resource" => @endpoint,
              "authorization_servers" => [@issuer],
              "scopes_supported" => ["tools:read"]
            })

          _ ->
            response(200, metadata)
        end
      end,
      request_fun: fn :post, {_url, headers, _type, body}, _, _ ->
        send(owner, {:token_request, URI.decode_query(body), headers})

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "private-access",
            "token_type" => "Bearer",
            "expires_in" => 300,
            "refresh_token" => "discarded-refresh"
          })}}
      end,
      connection_check: fn tenant, configuration ->
        send(owner, {:checked, tenant, configuration})
        {:ok, %{server_name: "Machine MCP", catalog: []}}
      end
    ]

    %{input: input, options: options}
  end

  test "machine connect obtains a token and validates MCP before returning private persistence data",
       data do
    assert {:ok, checked} = MCPConnectionProbe.check(data.options, "tenant", data.input)
    assert checked.connection.auth_method == "oauth"
    assert checked.connection.endpoint == @endpoint
    assert checked.connection.server_name == "Machine MCP"
    assert checked.secrets["grant_type"] == "client_credentials"
    assert checked.secrets["access_token"] == "private-access"
    assert checked.secrets["client_secret"] == "private-secret"
    assert checked.secrets["machine_metadata"]["issuer"] == @issuer
    assert {:ok, _, _} = DateTime.from_iso8601(checked.secrets["expires_at"])

    for field <- ~w(refresh_token redirect_uri code_verifier authorization_endpoint),
        do: refute(Map.has_key?(checked.secrets, field))

    refute inspect(checked) =~ "private-"

    assert_receive {:token_request, body, headers}
    assert body["grant_type"] == "client_credentials"
    assert body["resource"] == @endpoint
    assert body["scope"] == "tools:read"
    assert body["organization"] == "calendar"
    refute Map.has_key?(body, "headers")
    refute Enum.any?(headers, fn {key, _} -> to_string(key) == "x-workspace" end)
    assert_receive {:checked, "tenant", configuration}
    assert configuration.secrets["headers"] == data.input["credentials"]["headers"]
    assert configuration.secrets["token"] == "private-access"
    refute_received {:token_request, _, _}
  end

  test "public clients, browser grants and failed initialization cannot yield a machine connection",
       data do
    for credentials <- [
          data.input["credentials"]
          |> Map.put("client_auth_method", "none")
          |> Map.delete("client_secret"),
          Map.put(data.input["credentials"], "grant_type", "authorization_code")
        ] do
      assert {:error, _} =
               MCPConnectionProbe.check(data.options, "tenant", %{
                 data.input
                 | "credentials" => credentials
               })

      refute_received {:token_request, _, _}
    end

    options = Keyword.put(data.options, :connection_check, fn _, _ -> {:error, :failed} end)

    assert {:error, :mcp_connection_failed} =
             MCPConnectionProbe.check(options, "tenant", data.input)

    assert_receive {:token_request, _, _}
  end

  test "token HTTP and MCP checking cannot extend the machine token lifetime", data do
    requested_at = ~U[2026-11-07 00:00:00Z]
    clock = start_supervised!({Agent, fn -> requested_at end})
    request = Keyword.fetch!(data.options, :request_fun)

    options =
      data.options
      |> Keyword.put(:now, fn -> Agent.get(clock, & &1) end)
      |> Keyword.put(:request_fun, fn method, input, http, request_options ->
        Agent.update(clock, &DateTime.add(&1, 45))
        request.(method, input, http, request_options)
      end)
      |> Keyword.put(:connection_check, fn _, _ ->
        Agent.update(clock, &DateTime.add(&1, 120))
        {:ok, %{server_name: "Slow MCP", catalog: []}}
      end)

    assert {:ok, checked} = MCPConnectionProbe.check(options, "tenant", data.input)
    assert checked.secrets["expires_at"] == "2026-11-07T00:05:00Z"
  end

  defp response(status, body), do: {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
end
