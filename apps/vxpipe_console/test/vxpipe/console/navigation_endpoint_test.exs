defmodule Vxpipe.Console.NavigationEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  alias Vxpipe.Calls.Tenant
  alias Vxpipe.Console.Test.{FakeUserIdentity, NavigationIdentity, NavigationRepository}
  @endpoint Vxpipe.Console.Endpoint
  @key "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  setup do
    for {app, key} <- [
          {:vxpipe_calls, Vxpipe.Calls},
          {:vxpipe_console, :user_identity_backend},
          {:vxpipe_console, :navigation_test_principal},
          {:vxpipe_console, :navigation_test_status}
        ] do
      previous = Application.fetch_env(app, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end)
    end

    Application.put_env(:vxpipe_console, :user_identity_backend, NavigationIdentity)
    configure([tenant(@key), tenant(@other)])
    :ok
  end

  test "tenant creation checks page and API permissions and returns a dashboard destination" do
    member(["tenants.read"], %{})
    conn = login()
    assert conn |> recycle() |> get("/tenants/new") |> response(403)

    assert conn
           |> recycle()
           |> post("/admin/api/tenants", %{"name" => "Support"})
           |> json_response(403)

    refute_received {:created_tenant, _}

    member(["tenants.read", "tenants.write"], %{})
    assert conn |> recycle() |> get("/tenants/new") |> html_response(200) =~ "/assets/admin.js"

    created =
      conn
      |> recycle()
      |> post("/admin/api/tenants", %{"name" => " Support "})
      |> json_response(201)

    assert created["tenant"]["name"] == "Support"
    assert created["tenant"]["dashboard_path"] == "/t/#{created["tenant"]["key"]}/dashboard"
    refute Map.has_key?(created, "api_key")
    assert_received {:created_tenant, tenant}
    configure([tenant])

    dashboard =
      conn |> recycle() |> get(created["tenant"]["dashboard_path"]) |> html_response(200)

    assert dashboard =~ "/assets/admin.js"

    overview =
      conn |> recycle() |> get("/admin/api/tenants/#{tenant.key}/dashboard") |> json_response(200)

    refute Map.has_key?(overview, "recent_calls")

    assert Enum.all?(overview["tenant"]["capabilities"], fn {_resource, access} ->
             access == %{"read" => false, "write" => false}
           end)

    assert conn |> recycle() |> post("/admin/api/tenants", %{"name" => " "}) |> json_response(422) ==
             %{"error" => %{"code" => "invalid_tenant_name"}}

    assert build_conn()
           |> post("https://localhost/admin/api/tenants", %{"name" => "Support"})
           |> json_response(401)
  end

  test "directory Setup capability follows effective service write permission" do
    member(["tenant_services.read", "tenant_services.write"], %{@key => :read_write})
    conn = login()
    page = conn |> recycle() |> get("/admin/api/tenants") |> json_response(200)
    assert Enum.all?(page["tenants"], &(&1["can_setup"] == true))
    member(["tenant_services.read"])
    page = conn |> recycle() |> get("/admin/api/tenants") |> json_response(200)
    assert Enum.all?(page["tenants"], &(&1["can_setup"] == false))
  end

  test "login preserves a protected deep link and ignores external return parameters" do
    member(["calls.read"])
    anonymous = build_conn() |> get("https://localhost/t/#{@key}/calls?page=2")
    assert redirected_to(anonymous) == "/auth/login"

    authenticated =
      anonymous
      |> recycle()
      |> post("https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })

    assert json_response(authenticated, 200)
    returned = authenticated |> recycle() |> get("/")
    assert redirected_to(returned) == "/t/#{@key}/calls?page=2"

    assert returned |> recycle() |> get("/?return_to=https://example.test") |> redirected_to() ==
             "/t/#{@key}/dashboard"
  end

  test "authenticated bootstrap is private, scoped, and re-resolves permission changes" do
    member(["calls.read", "tenant_api_keys.read", "tenant_api_keys.write", "users.read"])
    conn = login()
    response = conn |> recycle() |> get("/admin/api/navigation?tenant=#{@key}")
    data = json_response(response, 200)
    assert data["landing_path"] == "/t/#{@key}/dashboard"
    assert data["directory_path"] == "/my-tenants"
    assert data["tenant_scope"] == "assigned"
    assert data["directory_access"]

    assert data["platform_destinations"] == [
             %{"id" => "users", "label" => "Users", "path" => "/users"}
           ]

    assert data["tenant"]["capabilities"]["calls"] == %{"read" => true, "write" => false}
    assert data["tenant"]["capabilities"]["api_keys"] == %{"read" => true, "write" => false}
    refute data["tenant"]["capabilities"]["services"]["read"]
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["private, no-store"]
    refute Map.has_key?(data, "tenants")

    member([])
    revoked = conn |> recycle() |> get("/admin/api/navigation?tenant=#{@key}")
    assert json_response(revoked, 404) == %{"error" => %{"code" => "tenant_not_found"}}
    Application.put_env(:vxpipe_console, :navigation_test_principal, {:error, :invalid_session})
    assert conn |> recycle() |> get("/admin/api/navigation") |> json_response(401)
  end

  test "all scope outranks assigned tenant count, including custom mixed roles" do
    member(["calls.read", "tenant_services.read"], %{@key => :read}, ["tenant_services.read"])
    data = login() |> recycle() |> get("/admin/api/navigation") |> json_response(200)
    assert data["landing_path"] == "/tenants"
    assert data["tenant_scope"] == "all"

    assert data["platform_destinations"] == [
             %{"id" => "tenants", "label" => "Tenants", "path" => "/tenants"}
           ]

    refute_received {:candidates, _, _}
  end

  test "multiple, stale and absent assignments use extant visibility; failures are not emptiness" do
    member(["calls.read"], %{@key => :read, @other => :read})
    conn = login()

    assert conn
           |> recycle()
           |> get("/admin/api/navigation")
           |> json_response(200)
           |> Map.fetch!("landing_path") == "/my-tenants"

    configure([tenant(@key)])

    assert conn
           |> recycle()
           |> get("/admin/api/navigation")
           |> json_response(200)
           |> Map.fetch!("landing_path") == "/t/#{@key}/dashboard"

    configure([])

    assert conn
           |> recycle()
           |> get("/admin/api/navigation")
           |> json_response(200)
           |> Map.fetch!("landing_path") == "/my-tenants"

    configure({:error, :repository_unavailable})
    assert conn |> recycle() |> get("/admin/api/navigation") |> json_response(503)
  end

  test "no tenant grants returns empty navigation without querying directory; foreign and missing identities match" do
    member([])
    conn = login()
    data = conn |> recycle() |> get("/admin/api/navigation") |> json_response(200)
    refute data["directory_access"]
    assert data["landing_path"] == "/my-tenants"
    refute_received {:candidates, _, _}
    assert conn |> recycle() |> get("/admin/api/tenants") |> json_response(403)

    member(["calls.read"])

    for path <- [
          "/admin/api/navigation?tenant=#{@other}",
          "/admin/api/navigation?tenant=not-valid",
          "/admin/api/navigation?tenant[]=#{@key}"
        ] do
      assert conn |> recycle() |> get(path) |> json_response(404) == %{
               "error" => %{"code" => "tenant_not_found"}
             }
    end
  end

  test "directory search bounds input and totals to current permission scope" do
    member(["calls.read"])

    data =
      login()
      |> recycle()
      |> get("/admin/api/tenants?q=  tenant &page_size=1")
      |> json_response(200)

    assert [%{"key" => @key, "dashboard_path" => "/t/#{@key}/dashboard"}] = data["tenants"]

    assert data["pagination"] == %{
             "page" => 1,
             "page_size" => 1,
             "total" => 1,
             "total_pages" => 1,
             "has_next" => false
           }

    assert_received {:search, {:keys, [@key]}, "tenant", 1, 0}

    for query <- [
          "page_size=51",
          "page_size[]=2",
          "q[]=bad",
          "page=0",
          "q=#{String.duplicate("a", 121)}"
        ] do
      assert login() |> recycle() |> get("/admin/api/tenants?#{query}") |> json_response(422)
    end

    member(["calls.read"], %{})

    assert %{"tenants" => [], "pagination" => %{"total" => 0}} =
             login() |> recycle() |> get("/admin/api/tenants") |> json_response(200)
  end

  test "dashboard returns only authorized data and separates empty from failed calls" do
    member(["tenant_api_keys.read"])
    conn = login()
    data = conn |> recycle() |> get("/admin/api/tenants/#{@key}/dashboard") |> json_response(200)
    assert data["tenant"]["key"] == @key
    refute Map.has_key?(data, "recent_calls")
    refute_received {:recent_calls, _, _}

    member(["calls.read"])

    assert %{"recent_calls" => %{"status" => "ready", "calls" => []}} =
             conn
             |> recycle()
             |> get("/admin/api/tenants/#{@key}/dashboard")
             |> json_response(200)

    assert_received {:recent_calls, @key, 5}

    configure([tenant(@key)], {:error, :repository_unavailable})

    assert %{"recent_calls" => %{"status" => "unavailable"}} =
             conn
             |> recycle()
             |> get("/admin/api/tenants/#{@key}/dashboard")
             |> json_response(200)

    for key <- [@other, "invalid"] do
      assert conn |> recycle() |> get("/admin/api/tenants/#{key}/dashboard") |> json_response(404) ==
               %{"error" => %{"code" => "tenant_not_found"}}
    end

    assert build_conn()
           |> get("https://localhost/admin/api/tenants/#{@key}/dashboard")
           |> json_response(401)
  end

  test "navigation rejects anonymous requests" do
    assert build_conn() |> get("https://localhost/admin/api/navigation") |> json_response(401)
  end

  test "root selects setup/login or the current user's authoritative landing" do
    assert build_conn() |> get("https://localhost/") |> redirected_to() == "/auth/login"
    Application.put_env(:vxpipe_console, :navigation_test_status, {:ok, :pending_first_run})
    assert build_conn() |> get("https://localhost/") |> redirected_to() == "/auth/setup"
    Application.put_env(:vxpipe_console, :navigation_test_status, {:ok, :complete})

    conn = login()
    all = conn |> recycle() |> get("/")
    assert redirected_to(all) == "/tenants"
    assert Plug.Conn.get_resp_header(all, "cache-control") == ["private, no-store"]
    member(["calls.read"])
    assert conn |> recycle() |> get("/") |> redirected_to() == "/t/#{@key}/dashboard"
    member(["calls.read"], %{@key => :read, @other => :read})
    assert conn |> recycle() |> get("/") |> redirected_to() == "/my-tenants"
    member([])
    assert conn |> recycle() |> get("/") |> redirected_to() == "/my-tenants"
    member(["calls.read"])
    configure({:error, :repository_unavailable})
    assert conn |> recycle() |> get("/") |> html_response(503) =~ "Try again"
  end

  test "canonical pages preserve page permissions and conceal foreign dashboards" do
    member(["calls.read", "tenant_api_keys.read"])
    conn = login()

    for path <- [
          "/my-tenants",
          "/account",
          "/t/#{@key}/dashboard",
          "/t/#{@key}/calls",
          "/t/#{@key}/services"
        ] do
      assert conn |> recycle() |> get(path) |> html_response(200) =~ "/assets/admin.js"
    end

    assert conn |> recycle() |> get("/tenants") |> redirected_to() == "/my-tenants"
    assert conn |> recycle() |> get("/t/#{@other}/dashboard") |> response(404)

    for path <- ["/users", "/roles", "/platform/services", "/t/#{@key}/call-specs"] do
      assert conn |> recycle() |> get(path) |> response(403)
    end
  end

  test "legacy page redirects preserve filters and keep editor/inspector and API URLs intact" do
    conn = login()

    assert conn
           |> recycle()
           |> get("/admin/tenants/#{@key}/calls?page=2&call_spec_id=delivery")
           |> redirected_to() == "/t/#{@key}/calls?call_spec_id=delivery&page=2"

    assert conn |> recycle() |> get("/admin/users/new") |> redirected_to() == "/users/new"

    assert conn |> recycle() |> get("/admin/tenants/#{@key}") |> redirected_to() ==
             "/t/#{@key}/dashboard"

    for path <- ["/admin/tenants/#{@key}/call-specs/new", "/admin/tenants/#{@key}/calls/call-id"] do
      assert conn |> recycle() |> get(path) |> html_response(200) =~ "/assets/admin.js"
    end

    assert conn |> recycle() |> get("/admin/api/navigation") |> json_response(200)
    assert build_conn() |> get("https://localhost/healthz") |> response(200)
  end

  test "new browser destinations retain the public plain-HTTP exclusion" do
    for path <- [
          "/",
          "/tenants",
          "/my-tenants",
          "/account",
          "/users",
          "/roles",
          "/platform/services",
          "/t/#{@key}/dashboard"
        ] do
      assert build_conn() |> get("http://public.example#{path}") |> response(404)
    end
  end

  defp login,
    do:
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })

  defp tenant(key),
    do: %Tenant{key: key, name: "Tenant #{key}", inserted_at: ~U[2026-10-13 00:00:00Z]}

  defp member(grants, assignments \\ %{@key => :read}, all \\ []) do
    principal = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(grants),
        assigned_tenants: assignments,
        all_tenant_actions: MapSet.new(all)
    }

    Application.put_env(:vxpipe_console, :navigation_test_principal, {:ok, principal})
  end

  defp configure(tenants, calls \\ {:ok, []}) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      settings
      |> Keyword.put(:admin_repository, {NavigationRepository, {self(), tenants, calls}})
      |> Keyword.put(:credential_repository, {NavigationRepository, self()})
    )
  end
end
