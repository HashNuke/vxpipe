defmodule Vxpipe.Console.AdminOnboardingEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias Vxpipe.Calls.Tenant

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-onboarding-secret-", 3)
  @token "operator-onboarding-token"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()
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

    assert_received {:demo_tenant_requested, %Tenant{name: "DemoTenant"}}
  end

  test "rejects missing authority or CSRF and reports unavailable storage" do
    configure_demo_repository({:error, :repository_unavailable})

    anonymous = post(build_conn(), "https://localhost/admin/api/onboarding/demo-tenant")
    assert json_response(anonymous, 401)["error"]["code"] == "operator_session_required"

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
      :admin_repository,
      {Vxpipe.Console.Test.AdminRepository, {self(), {:ok, {tenant, [], [], false}}}}
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
    form = https_get("/auth/login-token/#{@token}")

    form
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => csrf_token(form.resp_body),
      "operator" => %{"token" => @token, "code" => "01234567"}
    })
  end

  defp admin_csrf(authenticated) do
    page = authenticated |> recycle() |> https_get("/admin")
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    token
  end

  defp configure_login_repository do
    put_calls_repository(
      :operator_login_challenge_repository,
      {Vxpipe.Console.Test.OperatorLoginChallengeRepository, {self(), :ok}}
    )
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

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
