defmodule Vxpipe.Console.HomeController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.HomePage

  def index(conn, _params) do
    content = HomePage.render(%{})

    conn
    |> put_resp_header("cache-control", "no-store")
    |> html(Phoenix.HTML.Safe.to_iodata(content))
  end
end
