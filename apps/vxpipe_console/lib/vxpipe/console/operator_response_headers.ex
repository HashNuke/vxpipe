defmodule Vxpipe.Console.OperatorResponseHeaders do
  @moduledoc false

  @behaviour Plug

  alias Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{path_info: [prefix | _rest]} = conn, _options)
      when prefix in ["auth", "admin"] do
    conn
    |> Conn.put_resp_header("cache-control", "private, no-store")
    |> Conn.put_resp_header("referrer-policy", "no-referrer")
  end

  def call(%Conn{} = conn, _options), do: conn
end
