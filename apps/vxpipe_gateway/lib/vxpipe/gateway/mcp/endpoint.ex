defmodule Vxpipe.Gateway.MCP.Endpoint do
  @moduledoc "Authenticated, bounded HTTP mounting boundary for Vxpipe MCP."
  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Gateway.MCP.{Admission, Authentication, Handler, Protocol, Tools}
  alias Vxpipe.Gateway.OAuth.Configuration

  @impl true
  def init(options) do
    oauth = Configuration.build(options)

    %{
      oauth: oauth,
      enabled: Keyword.get(options, :enabled, false),
      resource_metadata: resource_metadata(oauth),
      allowed_hosts: Keyword.get(options, :allowed_hosts, []),
      allowed_origins: Keyword.get(options, :allowed_origins, []),
      allow_loopback_http: Keyword.get(options, :allow_loopback_http, false),
      admission: Keyword.get(options, :admission, Admission),
      authentication:
        Keyword.get(
          options,
          :authentication,
          {Authentication, [resource: Map.get(oauth, :resource)]}
        ),
      call_options: Keyword.get(options, :call_options, []),
      body_limit: positive_limit!(options, :body_limit, 131_072),
      read_timeout: positive_limit!(options, :read_timeout, 5_000),
      call_creation_timeout: positive_limit!(options, :call_creation_timeout, 100_000),
      protocol:
        ExMCP.HttpPlug.init(
          handler: Handler,
          handler_opts: {Handler, :options, []},
          principal_id: {Authentication, :principal_id, []},
          protocol_mode: :legacy_only,
          legacy_http_sse: false,
          oauth_enabled: false,
          cors_enabled: false,
          allowed_hosts: Keyword.get(options, :allowed_hosts, []),
          allowed_origins: Keyword.get(options, :allowed_origins, []),
          body_limit: positive_limit!(options, :body_limit, 131_072),
          handler_call_timeout: positive_limit!(options, :handler_call_timeout, 10_000)
        )
    }
  end

  @impl true
  def call(conn, options) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Configuration.resolve(options.oauth) do
      {:ok, current} -> call_current(conn, current_options(options, current))
      {:error, _reason} -> error(conn, 503, "unavailable")
    end
  end

  defp current_options(options, oauth) do
    admission = if oauth.resource_override, do: options.oauth, else: oauth

    authentication =
      case options.authentication do
        {Authentication, auth_options} ->
          {Authentication, Keyword.put(auth_options, :resource, Map.get(oauth, :resource))}

        custom ->
          custom
      end

    %{
      options
      | resource_metadata: resource_metadata(oauth),
        authentication: authentication,
        allowed_hosts: admission.allowed_hosts,
        allowed_origins: admission.allowed_origins,
        protocol:
          Map.merge(options.protocol, %{
            allowed_hosts: admission.allowed_hosts,
            allowed_origins: admission.allowed_origins
          })
    }
  end

  defp call_current(conn, options) do
    cond do
      not options.enabled or conn.path_info != ["mcp"] -> error(conn, 404, "not_found")
      conn.host not in options.allowed_hosts -> error(conn, 421, "host_not_allowed")
      not secure_transport?(conn, options) -> error(conn, 403, "https_required")
      not allowed_origin?(conn, options) -> error(conn, 403, "origin_not_allowed")
      true -> admit(conn, options)
    end
  end

  defp admit(conn, options) do
    case Admission.acquire(options.admission) do
      {:ok, lease} ->
        try do
          authenticate(conn, options)
        after
          Admission.release(options.admission, lease)
        end

      {:error, _reason} ->
        conn |> put_resp_header("retry-after", "1") |> error(503, "unavailable")
    end
  end

  defp authenticate(conn, options) do
    case Authentication.resolve(conn, options.authentication) do
      {:ok, actor, identity} ->
        conn
        |> delete_req_header("authorization")
        |> assign(:mcp_actor, actor)
        |> assign(:mcp_identity, identity)
        |> assign(:mcp_call_options, options.call_options)
        |> dispatch(options)

      {:error, :missing_credentials} ->
        conn
        |> put_resp_header("www-authenticate", challenge(options))
        |> error(401, "unauthorized")

      {:error, :invalid_credentials} ->
        conn
        |> put_resp_header("www-authenticate", challenge(options) <> ~s(, error="invalid_token"))
        |> error(401, "unauthorized")

      {:error, :malformed_credentials} ->
        error(conn, 400, "invalid_authorization")

      {:error, :authentication_unavailable} ->
        error(conn, 503, "unavailable")
    end
  end

  defp challenge(options),
    do: ~s(Bearer realm="vxpipe", resource_metadata="#{options.resource_metadata}", scope="mcp")

  defp resource_metadata(%{enabled: true, resource: resource}) do
    uri = URI.parse(resource)

    %{uri | path: "/.well-known/oauth-protected-resource" <> (uri.path || "")}
    |> URI.to_string()
  end

  defp resource_metadata(_disabled), do: nil

  defp dispatch(%{method: "POST"} = conn, options) do
    case read_body(conn,
           length: options.body_limit,
           read_length: options.body_limit,
           read_timeout: options.read_timeout
         ) do
      {:ok, body, conn} -> process_body(assign(conn, :raw_body, body), body, options)
      {:more, _body, conn} -> error(conn, 413, "body_too_large")
      {:error, _reason} -> error(conn, 400, "invalid_body")
    end
  end

  defp dispatch(%{method: "DELETE"} = conn, options) do
    if Protocol.valid_delete?(conn),
      do: ExMCP.HttpPlug.call(conn, options.protocol),
      else: error(conn, 400, "unsupported_protocol_version")
  end

  defp dispatch(conn, _options),
    do: conn |> put_resp_header("allow", "POST, DELETE") |> error(405, "method_not_allowed")

  defp process_body(conn, body, options) do
    case JSON.decode(body) do
      {:ok, request} ->
        case Protocol.validate(conn, request) do
          :ok -> authorize_tool(conn, request, options)
          {:error, code, message} -> reject_request(conn, request, code, message)
        end

      {:error, _reason} ->
        ExMCP.HttpPlug.call(conn, options.protocol)
    end
  end

  defp authorize_tool(conn, %{"method" => "tools/call", "params" => params} = request, options) do
    case Tools.authorize(
           conn.assigns.mcp_actor,
           params["name"],
           Map.get(params, "arguments", %{})
         ) do
      {:ok, _arguments} ->
        protocol =
          if params["name"] == "create_call",
            do: Map.put(options.protocol, :handler_call_timeout, options.call_creation_timeout),
            else: options.protocol

        ExMCP.HttpPlug.call(conn, protocol)

      {:error, :forbidden} ->
        error(conn, 403, "forbidden")

      {:error, _reason} ->
        reject_request(conn, request, -32602, "Invalid tool arguments")
    end
  end

  defp authorize_tool(conn, _request, options), do: ExMCP.HttpPlug.call(conn, options.protocol)

  defp reject_request(conn, request, code, message) do
    if Protocol.notification?(request),
      do: conn |> send_resp(202, "") |> halt(),
      else: protocol_error(conn, request, code, message)
  end

  defp protocol_error(conn, request, code, message) do
    id = Protocol.response_id(request)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      400,
      JSON.encode!(%{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
    )
    |> halt()
  end

  defp error(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(%{error: %{code: code}}))
    |> halt()
  end

  defp allowed_origin?(conn, options) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin in options.allowed_origins
      _multiple -> false
    end
  end

  defp secure_transport?(%{scheme: :https}, _options), do: true

  defp secure_transport?(conn, options) do
    options.allow_loopback_http and conn.host in ["localhost", "127.0.0.1", "::1", "[::1]"] and
      loopback?(conn.remote_ip)
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_address), do: false

  defp positive_limit!(options, key, default) do
    value = Keyword.get(options, key, default)
    if is_integer(value) and value > 0, do: value, else: raise(ArgumentError, "invalid MCP limit")
  end
end
