defmodule Vxpipe.MCP.AuthenticationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.Authentication

  test "builds only the closed none, bearer, and custom-header variants" do
    assert {:ok, []} = Authentication.headers(:none)
    assert {:ok, []} = Authentication.headers(nil)

    assert {:ok, [{"authorization", "Bearer private-token"}]} =
             Authentication.headers(type: :bearer, token: "private-token")

    assert {:ok, [{"x-api-key", "private-key"}, {"x-tenant", "tenant-one"}]} =
             Authentication.headers(
               type: :custom_headers,
               headers: [{"X-API-Key", "private-key"}, {"x-tenant", "tenant-one"}]
             )
  end

  test "rejects malformed credentials and transport-owned custom headers" do
    for authentication <- [
          [type: :bearer, token: ""],
          [type: :bearer, token: "part=part"],
          [type: :bearer, token: "value\r\ninjected"],
          [type: :custom_headers, headers: [{"bad header", "value"}]],
          [type: :custom_headers, headers: [{"x-valid", "value\nnext"}]],
          [type: :custom_headers, headers: [{"host", "other.example"}]],
          [type: :custom_headers, headers: [{"Content-Length", "12"}]],
          [type: :custom_headers, headers: [{"MCP-Session-Id", "session"}]],
          [
            type: :custom_headers,
            headers: [{"X-API-Key", "one"}, {"x-api-key", "two"}]
          ],
          [type: :other]
        ] do
      assert {:error, :invalid_authentication} = Authentication.headers(authentication)
    end
  end
end
