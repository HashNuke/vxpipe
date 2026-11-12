defmodule Vxpipe.Console.OAuth.Browser do
  @moduledoc "Validates the browser-facing OAuth boundary before session or consent work."
  @behaviour Plug
  import Plug.Conn
  alias Vxpipe.Console.ClientAddress
  alias Vxpipe.Gateway.OAuth.{Configuration, Input}
  alias Vxpipe.Identity.OAuth.Profile

  @binding_key "vxpipe_oauth_browser"
  @limit 16_384
  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    conn = Vxpipe.Console.PrivateNoStore.call(conn, [])
    options = Configuration.build(Application.get_env(:vxpipe_console, :oauth, []))

    with true <- options.enabled,
         {:ok, options} <- Configuration.resolve(options),
         :ok <- trusted_request(conn, options),
         :ok <- options.backend.rate_limit(:authorize, ClientAddress.for_throttling(conn)),
         {:ok, params, conn} <- input(conn, options.resource) do
      conn |> assign(:oauth_options, options) |> assign(:oauth_params, params)
    else
      false -> reject(conn, 404)
      {:error, :forbidden} -> reject(conn, 403)
      {:error, :rate_limited} -> reject(conn, 429)
      {:error, :unavailable} -> reject(conn, 503)
      {:error, status, updated} -> reject(updated, status)
      _invalid -> reject(conn, 400)
    end
  rescue
    _error -> reject(conn, 503)
  end

  def browser_binding(conn), do: get_session(conn, @binding_key)

  def ensure_binding(conn) do
    if opaque?(browser_binding(conn)),
      do: conn,
      else:
        put_session(
          conn,
          @binding_key,
          Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        )
  end

  def restore_binding(conn, value) do
    if opaque?(value), do: put_session(conn, @binding_key, value), else: conn
  end

  def opaque?(value) when is_binary(value) and byte_size(value) == 43 do
    case Base.url_decode64(value, padding: false) do
      {:ok, bytes} when byte_size(bytes) == 32 ->
        Base.url_encode64(bytes, padding: false) == value

      _invalid ->
        false
    end
  end

  def opaque?(_value), do: false

  defp trusted_request(conn, options) do
    issuer = URI.parse(options.issuer)
    origin = URI.to_string(%{issuer | path: nil})

    if conn.host in options.allowed_hosts and conn.host == issuer.host and
         Atom.to_string(conn.scheme) == issuer.scheme and conn.port == issuer.port and
         (conn.scheme == :https or conn.remote_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]) and
         issuer.path in [nil, "", "/"] and get_req_header(conn, "authorization") == [] and
         trusted_origin?(conn, origin),
       do: :ok,
       else: {:error, :forbidden}
  end

  # Native form navigation sends Origin: null under our no-referrer policy.
  # This exception is confined to consent POSTs, which still require the signed
  # browser binding, an authenticated session, and Plug's CSRF token check.
  defp trusted_origin?(%{method: "POST"} = conn, origin),
    do: get_req_header(conn, "origin") in [[], [origin], ["null"]]

  defp trusted_origin?(conn, origin),
    do: get_req_header(conn, "origin") in [[], [origin]]

  defp input(%{method: "GET", path_info: ["oauth", "authorize"]} = conn, resource) do
    with {:ok, params} <- query(conn.query_string),
         {:ok, params} <- Profile.authorization(params, resource) do
      {:ok, params, %{conn | query_params: params, params: params}}
    end
  end

  defp input(%{query_string: "", path_info: ["oauth", "authorize", id]} = conn, _resource) do
    if opaque?(id), do: decision_input(conn), else: {:error, :invalid_request}
  end

  defp input(_conn, _resource), do: {:error, :invalid_request}

  defp decision_input(%{method: "GET"} = conn), do: {:ok, %{}, conn}

  defp decision_input(%{method: "POST"} = conn) do
    with {:ok, params, conn} <- Input.read(conn, :form),
         true <- Enum.all?(Map.keys(params), &(&1 in ["decision", "_csrf_token"])),
         true <- params["decision"] in ["approve", "deny"] do
      {:ok, params,
       %{
         conn
         | body_params: params,
           query_params: %{},
           params: Map.merge(conn.path_params, params)
       }}
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  defp query(value) when byte_size(value) <= @limit do
    if String.valid?(value) and not Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, value) do
      value
      |> URI.query_decoder()
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, params} ->
        if Map.has_key?(params, key) or not String.valid?(key) or not String.valid?(value),
          do: {:halt, {:error, :invalid_request}},
          else: {:cont, {:ok, Map.put(params, key, value)}}
      end)
    else
      {:error, :invalid_request}
    end
  rescue
    _error -> {:error, :invalid_request}
  end

  defp query(_value), do: {:error, :invalid_request}

  defp reject(conn, status) do
    conn = Vxpipe.Console.PrivateNoStore.call(conn, [])
    conn = if status == 429, do: put_resp_header(conn, "retry-after", "60"), else: conn

    message =
      case status do
        429 -> "Too many authorization attempts. Try again shortly."
        503 -> "Authorization is temporarily unavailable. Try again."
        404 -> "Not found"
        _ -> "This authorization request is invalid. Start again from your client."
      end

    conn |> put_resp_content_type("text/plain") |> send_resp(status, message) |> halt()
  end
end
