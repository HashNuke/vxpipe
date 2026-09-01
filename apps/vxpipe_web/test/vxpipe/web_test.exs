defmodule Vxpipe.Web.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Vxpipe.Web.Router

  test "serves the health endpoint" do
    conn = Router.call(conn(:get, "/health"), Router.init([]))

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "reports that the core room runtime is ready" do
    conn = Router.call(conn(:get, "/ready"), Router.init([]))

    assert conn.status == 200
    assert conn.resp_body == "ready"
  end

  test "returns not found for an unknown route" do
    conn = Router.call(conn(:get, "/unknown"), Router.init([]))

    assert conn.status == 404
  end
end
