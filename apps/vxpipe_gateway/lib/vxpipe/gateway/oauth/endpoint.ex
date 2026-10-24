defmodule Vxpipe.Gateway.OAuth.Endpoint do
  @moduledoc "Public OAuth discovery and bounded registration, token and revocation endpoints."
  @behaviour Plug

  import Plug.Conn
  alias Vxpipe.Gateway.OAuth.{Configuration, Input}

  @metadata [:server_metadata, :resource_metadata]
  @errors [
    :invalid_request,
    :invalid_client,
    :invalid_client_metadata,
    :invalid_redirect_uri,
    :invalid_grant,
    :invalid_scope,
    :invalid_target,
    :unsupported_grant_type,
    :unauthorized_client,
    :access_denied
  ]
  @registration_fields ~w(client_id client_name redirect_uris grant_types response_types token_endpoint_auth_method scope client_uri client_id_issued_at)a
  @token_fields ~w(access_token token_type expires_in refresh_token scope)a

  @impl true
  def init(options), do: Configuration.build(options)

  def route?(conn, options),
    do: options.enabled and Map.has_key?(options.routes, conn.request_path)

  @impl true
  def call(conn, options) do
    case Configuration.resolve(options) do
      {:ok, current} ->
        call_current(conn, current)

      {:error, _reason} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> error(503, "temporarily_unavailable")
    end
  end

  defp call_current(conn, options) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

    cond do
      not route?(conn, options) -> error(conn, 404, "not_found")
      conn.host not in options.allowed_hosts -> error(conn, 421, "host_not_allowed")
      not secure_transport?(conn, options) -> error(conn, 403, "https_required")
      not allowed_origin?(conn, options) -> error(conn, 403, "origin_not_allowed")
      true -> conn |> cors() |> dispatch(Map.fetch!(options.routes, conn.request_path), options)
    end
  end

  defp dispatch(%{method: "OPTIONS"} = conn, operation, _options), do: preflight(conn, operation)

  defp dispatch(%{method: "GET"} = conn, operation, options) when operation in @metadata,
    do: respond(conn, 200, Configuration.metadata(operation, options))

  defp dispatch(%{method: "POST"} = conn, operation, options) when operation not in @metadata do
    cond do
      conn.query_string != "" -> error(conn, 400, "invalid_request")
      get_req_header(conn, "authorization") != [] -> error(conn, 400, "invalid_request")
      true -> process(conn, operation, options)
    end
  end

  defp dispatch(conn, operation, _options),
    do: conn |> put_resp_header("allow", methods(operation)) |> error(405, "invalid_request")

  defp process(conn, operation, options) do
    case rate_limit(options, operation, conn) do
      :ok ->
        case Input.read(conn, operation) do
          {:ok, params, conn} -> result(conn, operation, invoke(options, operation, params))
          {:error, status, conn} -> error(conn, status, "invalid_request")
        end

      error ->
        result(conn, operation, error)
    end
  end

  defp rate_limit(options, operation, conn) do
    with {:ok, address} <- client_address(conn, options.client_address_resolver) do
      safe_call(options.backend, :rate_limit, [operation, address])
    end
  end

  defp client_address(conn, resolver) do
    address =
      case resolver do
        nil -> conn.remote_ip |> :inet.ntoa() |> to_string()
        resolver when is_function(resolver, 1) -> resolver.(conn)
        _invalid -> nil
      end

    if canonical_address?(address), do: {:ok, address}, else: {:error, :unavailable}
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp canonical_address?(address) when is_binary(address) and byte_size(address) in 1..45 do
    with true <- String.valid?(address),
         {:ok, parsed} <- :inet.parse_strict_address(String.to_charlist(address)) do
      to_string(:inet.ntoa(parsed)) == address
    else
      _invalid -> false
    end
  end

  defp canonical_address?(_address), do: false

  defp invoke(options, :register, params),
    do: safe_call(options.backend, :register_client, [params])

  defp invoke(options, :token, params),
    do: safe_call(options.backend, :exchange, [params, options.resource])

  defp invoke(options, :revoke, params),
    do: safe_call(options.backend, :revoke, [params, options.resource])

  defp safe_call(backend, function, args) do
    apply(backend, function, args)
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp result(conn, :register, {:ok, response}) when is_map(response),
    do: respond(conn, 201, project(response, @registration_fields))

  defp result(conn, :token, {:ok, response}) when is_map(response),
    do: respond(conn, 200, project(response, @token_fields))

  defp result(conn, :revoke, :ok), do: conn |> send_resp(200, "") |> halt()

  defp result(conn, _operation, {:error, :rate_limited}),
    do: conn |> put_resp_header("retry-after", "60") |> error(429, "temporarily_unavailable")

  defp result(conn, _operation, {:error, reason}) when reason in @errors,
    do: error(conn, 400, Atom.to_string(reason))

  defp result(conn, _operation, _unknown), do: error(conn, 503, "temporarily_unavailable")

  defp project(response, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      case Map.fetch(response, field) do
        {:ok, value} ->
          Map.put(acc, Atom.to_string(field), value)

        :error ->
          case Map.fetch(response, Atom.to_string(field)) do
            {:ok, value} -> Map.put(acc, Atom.to_string(field), value)
            :error -> acc
          end
      end
    end)
  end

  defp preflight(conn, operation) do
    requested = get_req_header(conn, "access-control-request-method")
    headers = get_req_header(conn, "access-control-request-headers")
    method = if operation in @metadata, do: "GET", else: "POST"

    allowed_headers? =
      case headers do
        [] ->
          true

        [value] ->
          value
          |> String.downcase()
          |> String.split(",")
          |> Enum.all?(&(String.trim(&1) == "content-type"))

        _ ->
          false
      end

    if get_req_header(conn, "origin") != [] and requested == [method] and allowed_headers?,
      do:
        conn
        |> put_resp_header("access-control-allow-methods", method)
        |> put_resp_header("access-control-allow-headers", "content-type")
        |> send_resp(204, "")
        |> halt(),
      else: error(conn, 400, "invalid_request")
  end

  defp methods(operation) when operation in @metadata, do: "GET, OPTIONS"
  defp methods(_operation), do: "POST, OPTIONS"

  defp cors(conn) do
    conn = put_resp_header(conn, "vary", "Origin")

    case get_req_header(conn, "origin") do
      [origin] -> put_resp_header(conn, "access-control-allow-origin", origin)
      [] -> conn
    end
  end

  defp allowed_origin?(conn, options) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin in options.allowed_origins
      _ -> false
    end
  end

  defp secure_transport?(%{scheme: :https}, _options), do: true

  defp secure_transport?(conn, options),
    do:
      options.allow_loopback_http and conn.host in ["localhost", "127.0.0.1", "::1", "[::1]"] and
        loopback?(conn.remote_ip)

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_address), do: false

  defp error(conn, status, code), do: respond(conn, status, %{error: code})

  defp respond(conn, status, body),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, JSON.encode!(body))
      |> halt()
end
