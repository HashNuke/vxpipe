defmodule Vxpipe.Console.AdminOnboardingEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

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

  test "creates or resumes DemoTenant through an operator-authenticated CSRF write" do
    tenant = %Tenant{
      key: "DEMOabcdefgh1234",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:00:00Z]
    }

    configure_demo_repository({:ok, tenant})
    authenticated = authenticate()
    csrf = admin_csrf(authenticated)

    response =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/onboarding/demo-tenant")

    assert json_response(response, 200) == %{
             "tenant" => %{
               "key" => tenant.key,
               "name" => "DemoTenant",
               "created_at" => "2026-09-18T05:00:00Z"
             }
           }

    assert_received {:demo_tenant_requested, %Tenant{name: "Demo"}}
  end

  test "rejects missing authority or CSRF and reports unavailable storage" do
    configure_demo_repository({:error, :repository_unavailable})

    anonymous = post(build_conn(), "https://localhost/admin/api/onboarding/demo-tenant")
    assert json_response(anonymous, 401)["error"]["code"] == "session_required"

    authenticated = authenticate()

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
      |> put_req_header("x-csrf-token", "invalid")
      |> post("https://localhost/admin/api/onboarding/demo-tenant")
    end

    refute_received {:demo_tenant_requested, _candidate}

    csrf = admin_csrf(authenticated)

    unavailable =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/onboarding/demo-tenant")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "demo_tenant_unavailable"}
           }
  end

  test "keeps sample installation blocked until speech and model credentials exist" do
    tenant = %Tenant{
      key: "DEMOabcdefgh1234",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:00:00Z]
    }

    put_calls_repository(
      :provider_credential_repository,
      {Vxpipe.Console.Test.OperatorCredentialRepository,
       {self(), {:ok, %{tenant: %{key: tenant.key, name: tenant.name}, bindings: []}}}}
    )

    configure_demo_repository({:ok, tenant})

    authenticated = authenticate()
    csrf = admin_csrf(authenticated)

    response =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/onboarding/demo-tenant/samples")

    assert json_response(response, 422) == %{
             "error" => %{"code" => "sample_prerequisites_missing"}
           }
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp admin_csrf(authenticated) do
    page = authenticated |> recycle() |> https_get("/account")
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    token
  end

  defp configure_demo_repository(result) do
    put_calls_repository(
      :demo_tenant_repository,
      {Vxpipe.Console.Test.DemoTenantRepository, {self(), result}}
    )
  end

  defp put_calls_repository(key, repository) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.put(settings, key, repository))
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
