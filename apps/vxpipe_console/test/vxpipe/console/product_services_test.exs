defmodule Vxpipe.Console.ProductServicesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Console.{
    AdminServicesController,
    AdminTelephonyApplicationsController,
    RoutePermission
  }

  alias Vxpipe.Console.Test.{FakeUserIdentity, NavigationIdentity}
  @endpoint Vxpipe.Console.Endpoint
  @tenant "AAAAAAAAAAAAAAAA"
  @routes [
    {"GET", "/platform/services"},
    {"POST", "/platform/credentials/test"},
    {"POST", "/platform/credentials"},
    {"PATCH", "/platform/credentials/credential"},
    {"DELETE", "/platform/credentials/credential"},
    {"GET", "/tenants/#{@tenant}/services"},
    {"GET", "/tenants/#{@tenant}/service-bindings"},
    {"GET", "/tenants/#{@tenant}/credentials"},
    {"POST", "/tenants/#{@tenant}/credentials/test"},
    {"POST", "/tenants/#{@tenant}/credentials"},
    {"PATCH", "/tenants/#{@tenant}/credentials/credential"},
    {"DELETE", "/tenants/#{@tenant}/credentials/credential"},
    {"GET", "/tenants/#{@tenant}/telephony-applications"},
    {"POST", "/tenants/#{@tenant}/telephony-applications"},
    {"PATCH", "/tenants/#{@tenant}/telephony-applications/application"},
    {"GET", "/tenants/#{@tenant}/telephony-services/office/numbers"}
  ]

  setup do
    for key <- [:user_identity_backend, :navigation_test_principal, :telephony_host] do
      previous = Application.fetch_env(:vxpipe_console, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:vxpipe_console, key, value)
          :error -> Application.delete_env(:vxpipe_console, key)
        end
      end)
    end

    Application.put_env(:vxpipe_console, :user_identity_backend, NavigationIdentity)
    :ok
  end

  test "all service aliases deny explicit credentials before session fallback or JSON parsing" do
    auth = login()

    for prefix <- ["/api", "/admin/api"], {method, suffix} <- @routes do
      conn =
        auth
        |> recycle()
        |> put_req_header("authorization", "Bearer synthetic")
        |> put_req_header("content-type", "application/json")

      assert dispatch(conn, @endpoint, method, prefix <> suffix, "invalid-json")
             |> json_response(401) == %{"error" => %{"code" => "session_required"}}
    end
  end

  test "canonical routes retain exact legacy permissions and reject missing or insufficient sessions" do
    auth = login()

    actor = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    Application.put_env(:vxpipe_console, :navigation_test_principal, {:ok, actor})

    for {method, suffix} <- @routes do
      segments = String.split(suffix, "/", trim: true)
      expected = RoutePermission.for_request(method, ["admin", "api" | segments])
      refute expected == :unknown
      assert RoutePermission.for_request(method, ["api" | segments]) == expected

      assert dispatch(recycle(auth), @endpoint, method, "/api" <> suffix, %{})
             |> json_response(403)

      assert dispatch(build_conn(), @endpoint, method, "https://localhost/api" <> suffix, %{})
             |> json_response(401)
    end

    assert RoutePermission.for_request("GET", ["api", "platform", "credentials", "unexpected"]) ==
             :unknown
  end

  test "canonical service routes retain public HTTP and telephony host exclusions" do
    assert build_conn() |> get("http://public.example/api/platform/services") |> response(404)
    Application.put_env(:vxpipe_console, :telephony_host, "carrier.example")
    assert build_conn() |> get("https://carrier.example/api/platform/services") |> response(404)
  end

  test "controllers preserve domain forbidden responses without relying on router authorization" do
    actor = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    params = %{
      "tenant_key" => @tenant,
      "credential_id" => "credential",
      "service_id" => "application",
      "provider" => "deepgram",
      "values" => %{"api_key" => "synthetic"}
    }

    actions = [
      {AdminServicesController, :platform_index},
      {AdminServicesController, :tenant_bindings},
      {AdminServicesController, :index},
      {AdminServicesController, :index_credentials},
      {AdminServicesController, :validate},
      {AdminServicesController, :validate_platform},
      {AdminServicesController, :create},
      {AdminServicesController, :create_platform},
      {AdminServicesController, :update},
      {AdminServicesController, :update_platform},
      {AdminServicesController, :delete},
      {AdminServicesController, :delete_platform},
      {AdminTelephonyApplicationsController, :index},
      {AdminTelephonyApplicationsController, :create},
      {AdminTelephonyApplicationsController, :update}
    ]

    for {controller, action} <- actions do
      conn = build_conn() |> assign(:user_principal, actor)
      conn = %{conn | body_params: params}

      assert apply(controller, action, [conn, params]) |> json_response(403) == %{
               "error" => %{"code" => "forbidden"}
             }
    end
  end

  defp login do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end
end
