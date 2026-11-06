defmodule Vxpipe.Console.Test.OutboundMCPOAuthServer do
  @moduledoc "Controlled OAuth and MCP HTTP peer for outbound workflow acceptance."
  @behaviour Plug
  import Plug.Conn
  @resource "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"
  @origin "https://console.example.test"

  def resource, do: @resource
  def issuer, do: @issuer
  def origin, do: @origin

  def initial(mode),
    do: %{
      mode: mode,
      grant: "authorization_code",
      base: nil,
      count: %{},
      clients: %{},
      codes: %{},
      refresh: %{},
      access: MapSet.new(),
      sequence: 0,
      consent: :allow,
      mcp_fail: false,
      assertion_ids: MapSet.new(),
      authorization_parameters: %{},
      token_parameters: %{},
      mcp_headers: []
    }

  def configure(state, values), do: Agent.update(state, &Map.merge(&1, values))
  def count(state, key), do: Agent.get(state, &Map.get(&1.count, key, 0))
  def base(state), do: Agent.get(state, & &1.base)

  # Only these fixture adapters reroute validated public requests to the local peer.
  def options(state) do
    [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, {93, 184, 216, 34}, _options ->
        true = uri.host in ["mcp.example.test", "auth.example.test"]

        response =
          Req.get!(base(state) <> uri.path,
            decode_body: false,
            redirect: false,
            retry: false
          )

        {:ok,
         %{
           status: response.status,
           headers: Enum.flat_map(response.headers, fn {k, vs} -> Enum.map(vs, &{k, &1}) end),
           body: response.body
         }}
      end,
      request_fun: fn :post, {url, headers, type, body}, http, _ ->
        uri = URI.parse(to_string(url))
        true = uri.scheme == "https" and uri.host == "93.184.216.34"
        false = Keyword.fetch!(http, :autoredirect)
        headers = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

        response =
          Req.post!(base(state) <> uri.path,
            headers: [{"content-type", to_string(type)} | headers],
            body: body,
            decode_body: false,
            redirect: false,
            retry: false
          )

        {:ok, {{~c"HTTP/1.1", response.status, ~c"Fixture"}, [], response.body}}
      end,
      connection_check: fn tenant, configuration ->
        Vxpipe.MCP.ConnectionCheck.run_loopback_test(tenant, %{
          configuration
          | endpoint: base(state) <> "/mcp"
        })
      end
    ]
  end

  def authorize(state, authorization_url) do
    uri = URI.parse(authorization_url)
    Req.get!(base(state) <> uri.path <> "?" <> uri.query, redirect: false, retry: false)
  end

  @impl true
  def init(state), do: state
  @impl true
  def call(conn, state) do
    record(state, {conn.method, conn.request_path})
    route(conn, state)
  end

  defp route(%{method: "GET", request_path: "/mcp"} = conn, _state) do
    if get_req_header(conn, "authorization") == [] do
      conn
      |> put_resp_header(
        "www-authenticate",
        "Bearer resource_metadata=\"https://mcp.example.test/.well-known/oauth-protected-resource/mcp\""
      )
      |> json(401, %{})
    else
      send_resp(conn, 405, "")
    end
  end

  defp route(
         %{method: "GET", request_path: "/.well-known/oauth-protected-resource/mcp"} = conn,
         _state
       ),
       do:
         json(conn, 200, %{
           "resource" => @resource,
           "authorization_servers" => [@issuer],
           "scopes_supported" => ["tools:read"]
         })

  defp route(
         %{method: "GET", request_path: "/.well-known/oauth-authorization-server"} = conn,
         state
       ) do
    settings = Agent.get(state, & &1)
    cimd = settings.mode == "cimd"

    metadata = %{
      "issuer" => @issuer,
      "authorization_endpoint" => @issuer <> "/authorize",
      "token_endpoint" => @issuer <> "/token",
      "registration_endpoint" => @issuer <> "/register",
      "client_id_metadata_document_supported" => cimd,
      "authorization_response_iss_parameter_supported" => true,
      "response_types_supported" => ["code"],
      "grant_types_supported" => ["authorization_code", "refresh_token"],
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" =>
        if(cimd, do: ["none"], else: ["client_secret_basic"])
    }

    metadata =
      if settings.mode == "own_client" do
        metadata
        |> Map.delete("registration_endpoint")
        |> Map.put("token_endpoint_auth_methods_supported", [
          "none",
          "client_secret_basic",
          "client_secret_post",
          "private_key_jwt"
        ])
        |> Map.put("token_endpoint_auth_signing_alg_values_supported", ["RS256"])
      else
        metadata
      end

    metadata =
      if settings.grant == "client_credentials" do
        metadata
        |> Map.drop(
          ~w(authorization_endpoint response_types_supported code_challenge_methods_supported)
        )
        |> Map.put("grant_types_supported", ["client_credentials"])
      else
        metadata
      end

    json(conn, 200, metadata)
  end

  defp route(%{method: "POST", request_path: "/register"} = conn, state) do
    {:ok, body, conn} = read_body(conn)
    request = JSON.decode!(body)

    if request["redirect_uris"] == [@origin <> "/oauth/mcp/callback"] and
         request["token_endpoint_auth_method"] == "client_secret_basic" do
      client =
        Agent.get_and_update(state, fn s ->
          n = s.sequence + 1

          client = %{
            "client_id" => "fixture-client-#{n}",
            "client_secret" => "fixture-secret-#{n}",
            "client_secret_expires_at" => 0,
            "token_endpoint_auth_method" => "client_secret_basic",
            "redirect_uris" => request["redirect_uris"]
          }

          {client, %{s | sequence: n, clients: Map.put(s.clients, client["client_id"], client)}}
        end)

      json(conn, 201, client)
    else
      json(conn, 400, %{"error" => "invalid_client_metadata"})
    end
  end

  defp route(%{method: "GET", request_path: "/authorize"} = conn, state) do
    conn = fetch_query_params(conn)
    params = conn.query_params

    valid =
      params["redirect_uri"] == @origin <> "/oauth/mcp/callback" and
        params["resource"] == @resource and
        params["response_type"] == "code" and params["code_challenge_method"] == "S256" and
        params["scope"] == "tools:read" and registered?(state, params["client_id"]) and
        Agent.get(state, &contains_parameters?(params, &1.authorization_parameters))

    if valid do
      result =
        Agent.get_and_update(state, fn s ->
          if s.consent == :deny do
            {%{"error" => "access_denied"}, s}
          else
            n = s.sequence + 1
            code = "fixture-code-#{n}"
            {%{"code" => code}, %{s | sequence: n, codes: Map.put(s.codes, code, params)}}
          end
        end)

      query =
        result |> Map.merge(%{"state" => params["state"], "iss" => @issuer}) |> URI.encode_query()

      conn
      |> put_resp_header("location", params["redirect_uri"] <> "?" <> query)
      |> send_resp(303, "")
    else
      json(conn, 400, %{"error" => "invalid_request"})
    end
  end

  defp route(%{method: "POST", request_path: "/token"} = conn, state) do
    {:ok, body, conn} = read_body(conn)
    params = URI.decode_query(body)
    {client, method, credential} = authentication(conn, params)

    valid_parameters =
      Agent.get(state, &contains_parameters?(params, &1.token_parameters)) and
        get_req_header(conn, "x-workspace") == [] and not Map.has_key?(params, "private_key")

    if authenticated?(state, client, method, credential) and params["resource"] == @resource and
         valid_parameters do
      result = Agent.get_and_update(state, fn s -> redeem(s, client, params) end)

      case result do
        {:ok, tokens} -> json(conn, 200, tokens)
        :error -> json(conn, 400, %{"error" => "invalid_grant"})
      end
    else
      json(conn, 401, %{"error" => "invalid_client"})
    end
  end

  defp route(%{method: "POST", request_path: "/mcp"} = conn, state) do
    {:ok, body, conn} = read_body(conn)
    request = JSON.decode!(body)
    record(state, request["method"])

    authenticated =
      Agent.get(state, fn s ->
        Enum.any?(s.access, &(get_req_header(conn, "authorization") == ["Bearer " <> &1])) and
          Enum.all?(s.mcp_headers, fn {name, value} -> get_req_header(conn, name) == [value] end)
      end)

    if authenticated,
      do: rpc(conn, request, state),
      else: json(conn, 401, %{"error" => "unauthorized"})
  end

  defp route(%{method: "DELETE", request_path: "/mcp"} = conn, _state),
    do: send_resp(conn, 200, "")

  defp route(conn, _state), do: send_resp(conn, 404, "")

  defp rpc(conn, %{"method" => "notifications/initialized"}, _state), do: send_resp(conn, 202, "")

  defp rpc(conn, %{"method" => "initialize", "id" => id}, state) do
    if Agent.get(state, & &1.mcp_fail) do
      json(conn, 200, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => -32_000, "message" => "Fixture initialization rejected"}
      })
    else
      json(conn, 200, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{"tools" => %{}},
          "serverInfo" => %{"name" => "Fixture calendar", "version" => "1"}
        }
      })
    end
  end

  defp rpc(conn, %{"method" => "tools/list", "id" => id}, _state),
    do:
      json(conn, 200, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => %{
          "tools" => [
            %{
              "name" => "list_events",
              "inputSchema" => %{"type" => "object", "additionalProperties" => false}
            }
          ]
        }
      })

  defp rpc(conn, %{"id" => id}, _state),
    do:
      json(conn, 200, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => -32_601, "message" => "Unsupported"}
      })

  defp registered?(state, client),
    do:
      Agent.get(state, fn s ->
        Map.has_key?(s.clients, client) or
          (s.mode == "cimd" and client == @origin <> "/oauth/client-metadata.json")
      end)

  defp authenticated?(state, client, method, credential) do
    Agent.get_and_update(state, fn s ->
      case {Map.get(s.clients, client), method} do
        {%{"token_endpoint_auth_method" => ^method, "client_secret" => expected}, method}
        when method in ["client_secret_basic", "client_secret_post"] ->
          {credential == expected, s}

        {%{"token_endpoint_auth_method" => "none"}, "none"} ->
          {true, s}

        {%{"token_endpoint_auth_method" => "private_key_jwt"} = registered, "private_key_jwt"} ->
          verify_assertion(s, registered, client, credential)

        {nil, "none"} ->
          {s.mode == "cimd" and client == @origin <> "/oauth/client-metadata.json", s}

        _ ->
          {false, s}
      end
    end)
  end

  defp verify_assertion(s, registered, client, assertion) do
    case ExMCP.Authorization.JWT.verify_and_validate(assertion, registered["public_key"],
           iss: client,
           sub: client,
           aud: @issuer <> "/token"
         ) do
      {:ok, %{"jti" => id}} ->
        {not MapSet.member?(s.assertion_ids, id),
         %{s | assertion_ids: MapSet.put(s.assertion_ids, id)}}

      _ ->
        {false, s}
    end
  end

  defp authentication(conn, params) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        [client, secret] = encoded |> Base.decode64!() |> String.split(":", parts: 2)
        {URI.decode_www_form(client), "client_secret_basic", URI.decode_www_form(secret)}

      [] ->
        body_authentication(params)
    end
  end

  defp body_authentication(%{
         "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
         "client_assertion" => assertion,
         "client_id" => client
       }),
       do: {client, "private_key_jwt", assertion}

  defp body_authentication(%{"client_secret" => secret, "client_id" => client}),
    do: {client, "client_secret_post", secret}

  defp body_authentication(params), do: {params["client_id"], "none", nil}

  defp contains_parameters?(actual, expected),
    do: Enum.all?(expected, fn {key, value} -> actual[key] == value end)

  defp redeem(s, client, %{"grant_type" => "authorization_code"} = params) do
    {authorization, codes} = Map.pop(s.codes, params["code"])

    challenge =
      :crypto.hash(:sha256, params["code_verifier"] || "") |> Base.url_encode64(padding: false)

    if authorization && authorization["client_id"] == client &&
         authorization["redirect_uri"] == params["redirect_uri"] &&
         authorization["code_challenge"] == challenge,
       do: mint(%{s | codes: codes}, client),
       else: {:error, %{s | codes: codes}}
  end

  defp redeem(s, client, %{"grant_type" => "refresh_token"} = params) do
    {owner, refresh} = Map.pop(s.refresh, params["refresh_token"])
    if owner == client, do: mint(%{s | refresh: refresh}, client), else: {:error, s}
  end

  defp redeem(%{grant: "client_credentials"} = s, client, %{
         "grant_type" => "client_credentials",
         "scope" => "tools:read"
       }),
       do: mint(s, client)

  defp redeem(s, _client, _params), do: {:error, s}

  defp mint(s, client) do
    n = s.sequence + 1
    access = "fixture-access-#{n}"
    refresh = "fixture-refresh-#{n}"

    tokens = %{
      "access_token" => access,
      "refresh_token" => refresh,
      "token_type" => "Bearer",
      "expires_in" => 300
    }

    {{:ok, tokens},
     %{
       s
       | sequence: n,
         access: MapSet.put(s.access, access),
         refresh: Map.put(s.refresh, refresh, client)
     }}
  end

  defp record(state, key),
    do: Agent.update(state, &%{&1 | count: Map.update(&1.count, key, 1, fn n -> n + 1 end)})

  defp json(conn, status, body),
    do: conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
end
