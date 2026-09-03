defmodule Vxpipe.Gateway.HTTP.Endpoint do
  @moduledoc false

  @behaviour Plug

  alias Vxpipe.Gateway.HTTP.{Cors, Router}

  @impl true
  def init(options) do
    %{
      cors: options |> Keyword.get(:cors, []) |> Cors.init(),
      parsers:
        Plug.Parsers.init(
          parsers: [:json],
          pass: [],
          json_decoder: JSON,
          length: 131_072
        ),
      router:
        Router.init(
          room_creation: Keyword.get(options, :room_creation, []),
          webrtc: Keyword.get(options, :webrtc, [])
        )
    }
  end

  @impl true
  def call(conn, %{cors: cors_options, parsers: parser_options, router: router_options}) do
    conn = Cors.call(conn, cors_options)

    if conn.halted do
      conn
    else
      conn
      |> Plug.Parsers.call(parser_options)
      |> Router.call(router_options)
    end
  end
end
