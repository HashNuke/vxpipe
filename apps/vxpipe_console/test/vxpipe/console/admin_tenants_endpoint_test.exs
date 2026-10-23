defmodule Vxpipe.Console.AdminTenantsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.Tenant
  alias Vxpipe.Console.Test.FakeUserIdentity

  @endpoint Vxpipe.Console.Endpoint

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)

      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    :ok
  end

  test "returns one bounded tenant page to an installation operator" do
    tenants = [
      %Tenant{key: "BBBBBBBBBBBBBBBB", name: "Second", inserted_at: ~U[2026-09-17 02:00:00Z]},
      %Tenant{key: "AAAAAAAAAAAAAAAA", name: "First", inserted_at: ~U[2026-09-17 01:00:00Z]}
    ]

    configure_admin_repository({:ok, {tenants, 57}})

    conn =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants?page=2")

    assert json_response(conn, 200) == %{
             "tenants" => [
               %{
                 "key" => "BBBBBBBBBBBBBBBB",
                 "name" => "Second",
                 "dashboard_path" => "/t/BBBBBBBBBBBBBBBB/dashboard",
                 "can_setup" => true,
                 "created_at" => "2026-09-17T02:00:00Z"
               },
               %{
                 "key" => "AAAAAAAAAAAAAAAA",
                 "name" => "First",
                 "dashboard_path" => "/t/AAAAAAAAAAAAAAAA/dashboard",
                 "can_setup" => true,
                 "created_at" => "2026-09-17T01:00:00Z"
               }
             ],
             "pagination" => %{
               "page" => 2,
               "page_size" => 25,
               "total" => 57,
               "total_pages" => 3,
               "has_next" => true
             }
           }

    assert_received {:operator_tenants_requested, 25, 25}
  end

  test "keeps an empty result distinct from persistence failure" do
    configure_admin_repository({:ok, {[], 0}})

    empty = authenticate() |> recycle() |> https_get("/admin/api/tenants")
    assert %{"tenants" => [], "pagination" => %{"total" => 0}} = json_response(empty, 200)

    configure_admin_repository({:error, :database_unavailable})

    unavailable = authenticate() |> recycle() |> https_get("/admin/api/tenants")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "tenant_directory_unavailable"}
           }
  end

  test "rejects invalid pages and anonymous requests" do
    configure_admin_repository({:ok, {[], 0}})

    invalid =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants?page=zero")

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_tenants_requested, _, _}

    structured = authenticate() |> recycle() |> get("/admin/api/tenants?page[]=1")

    assert json_response(structured, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_tenants_requested, _, _}

    anonymous = https_get("/admin/api/tenants")

    assert json_response(anonymous, 401) == %{
             "error" => %{"code" => "session_required"}
           }

    refute_received {:operator_tenants_requested, _, _}
  end

  test "canonical directory uses the login session and refuses invalid explicit credentials" do
    mount = @endpoint.config(:gateway_mount)
    on_exit(fn -> Phoenix.Config.put(@endpoint, :gateway_mount, mount) end)

    Phoenix.Config.put(
      @endpoint,
      :gateway_mount,
      put_in(mount, [:endpoint, :router, :tenant_directory, :enabled], true)
    )

    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Canonical tenant",
      inserted_at: ~U[2026-10-15 00:00:00Z]
    }

    configure_admin_repository({:ok, {[tenant], 1}})
    authenticated = authenticate()
    response = authenticated |> recycle() |> https_get("/api/tenants")

    assert json_response(response, 200) == %{
             "items" => [
               %{
                 "tenant_key" => tenant.key,
                 "name" => tenant.name,
                 "created_at" => DateTime.to_iso8601(tenant.inserted_at)
               }
             ],
             "pagination" => %{"page" => 1, "page_size" => 25, "total" => 1, "total_pages" => 1}
           }

    assert_received {:operator_tenants_requested, 25, 0}

    denied =
      authenticated
      |> recycle()
      |> Plug.Conn.put_req_header("authorization", "Basic invalid")
      |> https_get("/api/tenants")

    assert json_response(denied, 401) == %{"error" => %{"code" => "invalid_api_key"}}
    refute_received {:operator_tenants_requested, _, _}

    assert json_response(https_get("/api/tenants"), 401) ==
             %{"error" => %{"code" => "session_required"}}
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp configure_admin_repository(result) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :admin_repository, {
        Vxpipe.Console.Test.AdminRepository,
        {self(), result}
      })
    )
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
