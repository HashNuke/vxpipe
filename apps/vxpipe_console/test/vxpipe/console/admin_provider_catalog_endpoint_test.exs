defmodule Vxpipe.Console.AdminProviderCatalogEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-call-specs-secret-", 3)
  @token "operator-admin-call-specs-token"
  @tenant_key "AAAAAAAAAAAAAAAA"

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

  test "operator catalog routes expose installed models and safe credential availability" do
    configure_repository({:ok, %{tenant: %{key: @tenant_key, name: "Example"}, bindings: []}})
    path = "/admin/api/tenants/#{@tenant_key}/providers"
    response = authenticate() |> recycle() |> https_get(path <> "?capability=text_to_speech")
    providers = json_response(response, 200)["providers"]
    assert Enum.any?(providers, &(&1["id"] == "deepgram" and not &1["credential_available"]))
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert_received {:operator_bindings_requested, @tenant_key}

    response =
      authenticate()
      |> recycle()
      |> https_get(path <> "/deepgram/models?capability=text_to_speech")

    assert [%{"id" => "flux", "voices" => %{"default" => "hannah"}}] =
             json_response(response, 200)["models"]

    refute response.resp_body =~ "api_key"
  end

  test "catalog errors distinguish invalid capability, unavailable provider and missing tenant" do
    configure_repository({:ok, %{tenant: %{key: @tenant_key, name: "Example"}, bindings: []}})
    path = "/admin/api/tenants/#{@tenant_key}/providers"

    for suffix <- ["", "?capability[]=text_to_speech", "?capability=invalid"] do
      response = authenticate() |> recycle() |> https_get(path <> suffix)
      assert json_response(response, 422) == %{"error" => %{"code" => "invalid_capability"}}
    end

    response =
      authenticate()
      |> recycle()
      |> https_get(path <> "/unknown/models?capability=text_to_speech")

    assert json_response(response, 404) == %{"error" => %{"code" => "provider_not_found"}}

    configure_repository({:error, :tenant_not_found})
    response = authenticate() |> recycle() |> https_get(path <> "?capability=text_to_speech")
    assert json_response(response, 404) == %{"error" => %{"code" => "tenant_not_found"}}

    configure_repository({:error, {:database_error, "private-sentinel"}})
    response = authenticate() |> recycle() |> https_get(path <> "?capability=text_to_speech")

    assert json_response(response, 503) == %{
             "error" => %{"code" => "provider_catalog_unavailable"}
           }
  end

  test "anonymous requests cannot query a tenant catalog" do
    response = https_get("/admin/api/tenants/#{@tenant_key}/providers?capability=text_to_speech")
    assert json_response(response, 401) == %{"error" => %{"code" => "operator_session_required"}}
    refute_received {:operator_bindings_requested, _}
  end

  test "platform onboarding receives model listings before any tenant exists" do
    configure_repository({:ok, %{tenant: nil, bindings: []}})
    response = authenticate() |> recycle() |> https_get("/admin/api/platform/services")

    assert [%{"id" => "flux", "voices" => %{"default" => "hannah"}}] =
             json_response(response, 200)["model_catalog"]["text_to_speech"]["deepgram"]
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

  defp configure_login_repository do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :operator_login_challenge_repository, {
        Vxpipe.Console.Test.OperatorLoginChallengeRepository,
        {self(), :ok}
      })
    )
  end

  defp configure_repository(result) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :provider_credential_repository, {
        Vxpipe.Console.Test.OperatorCredentialRepository,
        {self(), result}
      })
    )
  end

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
