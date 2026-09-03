defmodule Vxpipe.Gateway.HTTP.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint

  @allowed_origin "https://client.example.test"
  @endpoint_options Endpoint.init(
                      cors: [
                        allowed_origins: [@allowed_origin],
                        allowed_methods: ["POST", "PATCH", "OPTIONS"],
                        allowed_headers: ["content-type", "authorization"],
                        allow_credentials: false
                      ]
                    )

  test "answers health checks" do
    conn =
      :get
      |> conn("/healthz")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "answers a preflight request from a configured origin" do
    conn =
      :options
      |> conn("/api/rtvi/offer")
      |> put_req_header("origin", @allowed_origin)
      |> put_req_header("access-control-request-method", "PATCH")
      |> put_req_header("access-control-request-headers", "content-type,authorization")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == [@allowed_origin]
    assert get_resp_header(conn, "access-control-allow-methods") == ["POST,PATCH,OPTIONS"]
    assert get_resp_header(conn, "access-control-allow-headers") == ["content-type,authorization"]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "does not grant a non-configured origin" do
    conn =
      :get
      |> conn("/healthz")
      |> put_req_header("origin", "https://untrusted.example.test")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end
end
