defmodule Vxpipe.Console.ProductAPIKeysTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Console.Test.{AccessKeyRepository, FakeUserIdentity, NavigationIdentity}
  @endpoint Vxpipe.Console.Endpoint
  @tenant "AAAAAAAAAAAAAAAA"
  @attrs %{"name" => "Backend", "kind" => "calls", "tenant_key" => @tenant}

  setup do
    for {app, key} <- [
          {:vxpipe_calls, Vxpipe.Calls},
          {:vxpipe_console, :user_identity_backend},
          {:vxpipe_console, :navigation_test_principal},
          {:vxpipe_console, :telephony_host}
        ] do
      original = Application.fetch_env(app, key)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end)
    end

    Application.put_env(:vxpipe_console, :user_identity_backend, NavigationIdentity)
    options = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(options, :access_key_repository, {AccessKeyRepository, self()})
    )

    member(~w(access_keys.read access_keys.write calls.read calls.write))
    :ok
  end

  test "canonical and legacy endpoints share scoped listings, issuance and revocation" do
    auth = login()

    for prefix <- ["/api/api-keys", "/admin/api/api-keys"] do
      page = auth |> recycle() |> get(prefix <> "?q=Backend&page=1")
      assert get_resp_header(page, "cache-control") == ["private, no-store"]

      assert %{"keys" => [%{"last_four" => "abcd"}], "creatable_kinds" => ["calls"]} =
               json_response(page, 200)

      refute page.resp_body =~ "secret"
      assert_received {:key_list, {:keys, [@tenant]}, false, %{query: "Backend", limit: 25}}

      assert %{"tenants" => [%{"key" => @tenant}]} =
               auth |> recycle() |> get(prefix <> "/tenants?kind=calls") |> json_response(200)

      assert_received {:key_tenants, {:keys, [@tenant]}, _}
      issued = auth |> recycle() |> post(prefix, @attrs) |> json_response(201)
      assert String.starts_with?(issued["secret"], "vxak_")
      assert issued["key"]["can_revoke"]
      assert_received {:key_insert, %{tenant_key: @tenant, scopes: ["calls"]}}
      assert auth |> recycle() |> delete(prefix <> "/" <> issued["key"]["id"]) |> response(204)
    end
  end

  test "session-only routes reject explicit Authorization before parsing or cookie fallback" do
    auth = login()

    for prefix <- ["/api/api-keys", "/admin/api/api-keys"],
        headers <- [
          [""],
          ["Basic synthetic"],
          ["Bearer vxpk_" <> String.duplicate("a", 43)],
          ["Bearer vxak_" <> String.duplicate("b", 43)],
          ["Bearer a", "Bearer b"]
        ] do
      conn = auth |> recycle() |> put_req_header("content-type", "application/json")
      conn = %{conn | req_headers: Enum.map(headers, &{"authorization", &1}) ++ conn.req_headers}

      assert conn |> post(prefix, "invalid-json") |> json_response(401) ==
               %{"error" => %{"code" => "session_required"}}
    end

    refute_received {:key_insert, _}
    assert build_conn() |> get("https://localhost/api/api-keys") |> json_response(401)
  end

  test "current authority and tenant delegation bound canonical writes" do
    auth = login()

    for attrs <- [
          %{@attrs | "tenant_key" => "BBBBBBBBBBBBBBBB"},
          %{"name" => "Platform", "kind" => "platform"}
        ] do
      assert auth |> recycle() |> post("/api/api-keys", attrs) |> json_response(403)
    end

    member(~w(access_keys.read))
    assert auth |> recycle() |> post("/api/api-keys", @attrs) |> json_response(403)

    assert auth
           |> recycle()
           |> delete("/api/api-keys/01900000-0000-7000-8000-000000000001")
           |> json_response(403)

    refute_received {:key_insert, _}
    Application.put_env(:vxpipe_console, :navigation_test_principal, {:error, :invalid_session})
    assert auth |> recycle() |> get("/api/api-keys") |> json_response(401)
  end

  test "canonical mutations preserve browser CSRF checks" do
    auth = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, auth.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      auth
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("x-csrf-token", "invalid")
      |> post("/api/api-keys", @attrs)
    end

    refute_received {:key_insert, _}

    assert auth
           |> recycle()
           |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
           |> put_req_header("x-csrf-token", csrf)
           |> post("/api/api-keys", @attrs)
           |> json_response(201)
  end

  test "Console ownership is exact and leaves Gateway endpoints intact" do
    auth = login()

    for {method, path} <- [
          {:patch, "/api/api-keys/key"},
          {:get, "/api/api-keys/key"},
          {:get, "/api/api-keys/tenants/extra"}
        ] do
      assert dispatch(recycle(auth), @endpoint, method, path, nil).status == 404
    end

    assert build_conn() |> get("https://localhost/healthz") |> response(200)
  end

  test "canonical keys preserve public HTTP and telephony host exclusions" do
    assert build_conn() |> get("http://public.example/api/api-keys") |> response(404)
    Application.put_env(:vxpipe_console, :telephony_host, "carrier.example")
    assert build_conn() |> get("https://carrier.example/api/api-keys") |> response(404)
  end

  defp login do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp member(grants) do
    actor = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(grants),
        assigned_tenants: %{@tenant => :read_write},
        all_tenant_actions: MapSet.new()
    }

    Application.put_env(:vxpipe_console, :navigation_test_principal, {:ok, actor})
  end
end
