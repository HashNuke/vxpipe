defmodule Vxpipe.Gateway.HTTP.Endpoint do
  @moduledoc false

  @behaviour Plug

  alias Vxpipe.Gateway.HTTP.{Cors, Router}

  @impl true
  def init(options) do
    %{
      cors: options |> Keyword.get(:cors, []) |> Cors.init(),
      router: Router.init([])
    }
  end

  @impl true
  def call(conn, %{cors: cors_options, router: router_options}) do
    conn = Cors.call(conn, cors_options)

    if conn.halted do
      conn
    else
      Router.call(conn, router_options)
    end
  end
end
