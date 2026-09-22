defmodule Vxpipe.Console.TelephonyHostGuard do
  @moduledoc "Restricts the configured public telephony host to carrier ingress routes."

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    if public_host?(conn.host) and not allowed_path?(conn.path_info) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "not found")
      |> halt()
    else
      conn
    end
  end

  @spec public_host?(String.t()) :: boolean()
  def public_host?(host) when is_binary(host) do
    case Application.get_env(:vxpipe_console, :telephony_host) do
      configured when is_binary(configured) ->
        String.downcase(host) == String.downcase(configured)

      _missing ->
        false
    end
  end

  def public_host?(_host), do: false

  defp allowed_path?(["healthz"]), do: true
  defp allowed_path?(["webhooks", "platform", "telnyx"]), do: true
  defp allowed_path?(["webhooks", "tenants", _tenant, "telnyx"]), do: true
  defp allowed_path?(["api", "telephony", "telnyx" | _rest]), do: true
  defp allowed_path?(["api", "telephony", "twilio" | _rest]), do: true
  defp allowed_path?(_path), do: false
end
