defmodule Vxpipe.Console.CallConsolePageTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Console.TestOperatorAuthenticator

  @endpoint Vxpipe.Console.Endpoint
  @call_id "call-public-id"
  @tenant_key "tenantkey1234567"

  setup do
    original = Application.fetch_env!(:vxpipe_console, :operator_authenticator)

    on_exit(fn -> Application.put_env(:vxpipe_console, :operator_authenticator, original) end)

    Application.put_env(
      :vxpipe_console,
      :operator_authenticator,
      {TestOperatorAuthenticator, self()}
    )

    :ok
  end

  test "requires the calls-scoped operator session" do
    assert redirected_to(get(build_conn(), route()), 302) == "/operator/sign-in"
  end

  test "serves the reusable call console host for the requested call" do
    response = sign_in() |> recycle() |> get(route()) |> html_response(200)

    assert response =~ ~s(id="call-console-root")
    assert response =~ ~s(data-call-id="#{@call_id}")
    assert response =~ ~s(data-tenant-key="#{@tenant_key}")
    assert response =~ ~s(src="/assets/debug_console.js")
    assert response =~ ~s(href="/assets/debug_console.css")
    refute response =~ "valid-api-key"
  end

  test "does not serve a call through another tenant namespace" do
    conn = sign_in() |> recycle() |> get("/tenants/other-tenant-key/calls/#{@call_id}/console")

    assert response(conn, 404)
  end

  test "escapes the call identity in the host document" do
    response =
      sign_in()
      |> recycle()
      |> get(
        "/tenants/#{@tenant_key}/calls/%22%3E%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E/console"
      )
      |> html_response(200)

    refute response =~ "<img src=x onerror=alert(1)>"
  end

  defp route, do: "/tenants/#{@tenant_key}/calls/#{@call_id}/console"

  defp sign_in do
    build_conn()
    |> init_test_session(%{})
    |> post("/operator/session", %{
      "operator" => %{"tenant_key" => @tenant_key, "api_key" => "valid-api-key"}
    })
  end
end
