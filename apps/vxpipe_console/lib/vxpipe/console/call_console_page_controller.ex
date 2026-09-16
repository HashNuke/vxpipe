defmodule Vxpipe.Console.CallConsolePageController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.CallConsolePage

  def show(conn, %{"call_id" => call_id}) do
    content = CallConsolePage.render(%{call_id: call_id})

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> html(Phoenix.HTML.Safe.to_iodata(content))
  end
end
