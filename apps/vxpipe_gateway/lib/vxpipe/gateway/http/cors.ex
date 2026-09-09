defmodule Vxpipe.Gateway.HTTP.Cors do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(options), do: options |> cors_plug_options() |> CORSPlug.init()

  @impl true
  def call(%Plug.Conn{} = conn, options) do
    if backend_only_path?(conn.path_info), do: conn, else: CORSPlug.call(conn, options)
  end

  defp cors_plug_options(options) do
    [
      origin: Keyword.get(options, :allowed_origins, []),
      methods: Keyword.get(options, :allowed_methods, ["GET", "POST", "PATCH", "OPTIONS"]),
      headers: Keyword.get(options, :allowed_headers, ["content-type", "authorization"]),
      credentials: Keyword.get(options, :allow_credentials, false)
    ]
  end

  defp backend_only_path?([
         "api",
         "tenants",
         _tenant_key,
         "participants",
         _participant_key,
         "calls"
       ]),
       do: true

  defp backend_only_path?([
         "api",
         "tenants",
         _tenant_key,
         "calls",
         _call_id,
         "participants",
         _participant_key,
         "join-tokens"
       ]),
       do: true

  defp backend_only_path?(_path), do: false
end
