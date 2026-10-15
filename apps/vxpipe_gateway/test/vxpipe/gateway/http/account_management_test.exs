defmodule Vxpipe.Gateway.HTTP.AccountManagementTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias Vxpipe.Gateway.HTTP.AccountManagement
  alias Vxpipe.Gateway.Test.AccountStore

  test "canonical endpoints authenticate platform keys and preserve safe HTTP envelopes" do
    response = request("GET", ["users"])
    assert response.status == 200

    assert %{"users" => [%{"id" => _, "roleId" => _}], "pagination" => %{"page_size" => 25}} =
             JSON.decode!(response.resp_body)

    assert get_resp_header(response, "cache-control") == ["no-store"]
    refute response.resp_body =~ "private-password-hash"

    assert request("GET", ["users", AccountStore.user_id()]).status == 200
    assert request("POST", ["users"], body: input()).status == 201

    assert request("PATCH", ["users", AccountStore.user_id()], body: %{"enabled" => false}).status ==
             200

    assert request("POST", ["users", AccountStore.user_id(), "disable"]).status == 200
    roles = request("GET", ["role-options"])
    assert %{"roles" => [%{"kind" => nil}], "pagination" => %{}} = JSON.decode!(roles.resp_body)
    assert request("GET", ["users"], enabled: false).status == 404
  end

  test "browser authentication preserves response hooks and rejects invalid explicit credentials" do
    assert request("GET", ["users"], secret: nil, browser: :allowed).status == 200
    assert_received :browser_authenticated
    invalid = request("GET", ["users"], secret: nil, browser: :allowed, query: "page_size=51")
    assert invalid.status == 422
    assert get_resp_header(invalid, "x-browser-response") == ["preserved"]
    assert_received :browser_authenticated

    assert request("GET", ["users"], secret: "bad", browser: :allowed).status == 401
    refute_received :browser_authenticated
    assert request("GET", ["users"], secret: "tenant-key").status == 403
    assert request("GET", ["users"], secret: nil).status == 401
    assert request("GET", ["users"], secret: nil, browser: :denied).status == 403
  end

  test "browser CSRF failures retain their forbidden transport behavior" do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      request("POST", ["users"], secret: nil, browser: :csrf, body: input())
    end
  end

  test "canonical inputs reject legacy aliases and storage failures remain private" do
    unknown_membership =
      Map.put(input(), "memberships", [%{"tenant_key" => "BBBBBBBBBBBBBBBB", "access" => "read"}])

    assert request("POST", ["users"], body: unknown_membership).status == 422
    assert request("GET", ["users"], query: "q=legacy").status == 422
    assert request("GET", ["role-options"], query: "query=ignored").status == 422

    assert request("POST", ["users"],
             body:
               Map.put(input(), "memberships", [
                 %{"tenant_id" => "AAAAAAAAAAAAAAAA", "access" => "read"}
               ])
           ).status == 422

    assert request("POST", ["users", AccountStore.user_id(), "disable"],
             body: %{"email" => "unexpected"}
           ).status == 422

    for failure <- [:raise, :exit, :error] do
      Process.put({AccountStore, :failure}, failure)
      response = request("GET", ["users"])
      assert response.status == 503
      refute response.resp_body =~ "private"
    end
  end

  def authenticate(_conn, :csrf), do: raise(Plug.CSRFProtection.InvalidCSRFTokenError)

  def authenticate(conn, access) do
    send(self(), :browser_authenticated)

    actor = %Vxpipe.Identity.Principal{
      user_public_id: AccountStore.user_id(),
      session_public_id: AccountStore.key_id(),
      account_kind: :member,
      grants: MapSet.new(if(access == :allowed, do: ["users.read"], else: []))
    }

    {:ok, register_before_send(conn, &put_resp_header(&1, "x-browser-response", "preserved")),
     actor}
  end

  defp request(method, segments, options \\ []) do
    query = Keyword.get(options, :query, "")
    conn = Plug.Test.conn(method, "/api/" <> Enum.join(segments, "/") <> "?" <> query)
    conn = %{conn | body_params: Keyword.get(options, :body, %{})}
    secret = Keyword.get(options, :secret, AccountStore.platform_secret())
    conn = if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn

    browser =
      if Keyword.get(options, :browser), do: {__MODULE__, Keyword.fetch!(options, :browser)}

    config =
      AccountManagement.init(
        enabled: Keyword.get(options, :enabled, true),
        browser_auth: browser,
        calls_options: [
          credential_repository: {AccountStore, nil},
          access_key_repository: {AccountStore, nil}
        ],
        identity_options: [identity_dependencies: AccountStore.dependencies()]
      )

    AccountManagement.route(conn, config, segments)
  end

  defp input,
    do: %{
      "email" => "member@example.test",
      "role_id" => AccountStore.role_id(),
      "password" => "long test password",
      "password_confirmation" => "long test password"
    }
end
