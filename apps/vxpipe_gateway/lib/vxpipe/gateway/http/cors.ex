defmodule Vxpipe.Gateway.HTTP.Cors do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(options) do
    options
    |> cors_plug_options()
    |> CORSPlug.init()
  end

  @impl true
  def call(conn, options), do: CORSPlug.call(conn, options)

  defp cors_plug_options(options) do
    [
      origin: Keyword.get(options, :allowed_origins, []),
      methods: Keyword.get(options, :allowed_methods, ["GET", "POST", "PATCH", "OPTIONS"]),
      headers: Keyword.get(options, :allowed_headers, ["content-type", "authorization"]),
      credentials: Keyword.get(options, :allow_credentials, false)
    ]
  end
end
