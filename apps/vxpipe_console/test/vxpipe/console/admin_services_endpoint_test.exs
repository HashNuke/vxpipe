defmodule Vxpipe.Console.AdminServicesEndpointTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias Vxpipe.Calls.{ProviderCredential, TelephonyService, Tenant}

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-services-secret-", 3)
  @token "operator-admin-services-token"
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

  test "returns only tenant credential and telephony metadata" do
    tenant = tenant()

    credential = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: @tenant_key,
      provider: "telnyx",
      name: "voice",
      auth_kind: "api_key",
      status: :active,
      inserted_at: ~U[2026-09-17 02:00:00Z],
      updated_at: ~U[2026-09-17 02:00:00Z]
    }

    service = %TelephonyService{
      id: "22222222-2222-4222-8222-222222222222",
      tenant_key: @tenant_key,
      name: "support",
      ingress_key: "support-ingress",
      provider: "telnyx",
      provider_connection_id: "connection-primary",
      credential_id: credential.id,
      public_key: nil,
      outbound_number: "+14155550100",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300,
      inserted_at: ~U[2026-09-17 02:05:00Z],
      updated_at: ~U[2026-09-17 02:05:00Z]
    }

    configure_admin_repository({:ok, {tenant, [credential], [service], false}})

    conn = authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/services")

    assert json_response(conn, 200) == %{
             "tenant" => %{"key" => @tenant_key, "name" => "Example tenant"},
             "credentials" => [
               %{
                 "id" => credential.id,
                 "provider" => "telnyx",
                 "name" => "voice",
                 "auth_kind" => "api_key",
                 "status" => "active",
                 "created_at" => "2026-09-17T02:00:00Z",
                 "updated_at" => "2026-09-17T02:00:00Z"
               }
             ],
             "telephony_services" => [
               %{
                 "id" => service.id,
                 "name" => "support",
                 "provider" => "telnyx",
                 "provider_connection_id" => "connection-primary",
                 "credential_id" => credential.id,
                 "outbound_number" => "+14155550100"
               }
             ],
             "truncated" => false
           }

    refute conn.resp_body =~ "payload"
    refute conn.resp_body =~ "encryption_key"
    assert_received {:operator_services_requested, @tenant_key}
  end

  test "creates supported credentials with CSRF and never echoes or logs secret fields" do
    for {provider, values, expected_kind, expected_payload} <- [
          {"google", %{"api_key" => "google-private"}, "api_key",
           %{"api_key" => "google-private"}},
          {"deepgram", %{"api_key" => "deepgram-private"}, "api_key",
           %{"api_key" => "deepgram-private"}},
          {"zenmux", %{"api_key" => "zenmux-private"}, "api_key",
           %{"api_key" => "zenmux-private"}},
          {"telnyx", %{"api_key" => "telnyx-private"}, "api_key",
           %{"api_key" => "telnyx-private"}},
          {"twilio",
           %{
             "account_sid" => "AC11111111111111111111111111111111",
             "auth_token" => "twilio-private"
           }, "account_sid_auth_token",
           %{
             "account_sid" => "AC11111111111111111111111111111111",
             "auth_token" => "twilio-private"
           }}
        ] do
      returned = %ProviderCredential{
        id: "11111111-1111-4111-8111-111111111111",
        tenant_key: @tenant_key,
        provider: provider,
        name: "primary",
        auth_kind: expected_kind,
        inserted_at: ~U[2026-09-17 02:00:00Z],
        updated_at: ~U[2026-09-17 02:00:00Z]
      }

      configure_credential_repository({:ok, returned})
      authenticated = authenticate()
      csrf = admin_csrf(authenticated)
      returned_id = returned.id

      log =
        capture_log([level: :debug], fn ->
          response =
            authenticated
            |> recycle()
            |> put_req_header("x-csrf-token", csrf)
            |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
              "provider" => provider,
              "name" => "primary",
              "values" => values
            })

          assert %{
                   "credential" => %{
                     "id" => ^returned_id,
                     "provider" => ^provider,
                     "name" => "primary",
                     "auth_kind" => ^expected_kind,
                     "status" => "active"
                   }
                 } = json_response(response, 201)

          for secret <- Map.values(values), do: refute(response.resp_body =~ secret)
        end)

      for secret <- Map.values(values), do: refute(log =~ secret)
      assert_received {:operator_credential_created, created, ^expected_payload}
      assert created.tenant_key == @tenant_key
      assert created.provider == provider
    end
  end

  test "preserves not-found, unavailable, conflict, invalid, CSRF, and anonymous outcomes" do
    configure_admin_repository({:error, :tenant_not_found})

    missing =
      authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/services")

    assert json_response(missing, 404) == %{"error" => %{"code" => "tenant_not_found"}}

    configure_admin_repository({:error, :database_unavailable})

    unavailable =
      authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/services")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "service_directory_unavailable"}
           }

    authenticated = authenticate()
    csrf = admin_csrf(authenticated)
    configure_credential_repository({:error, :provider_credential_conflict})

    conflict =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
        "provider" => "google",
        "name" => "primary",
        "values" => %{"api_key" => "duplicate-private"}
      })

    assert json_response(conflict, 409) == %{
             "error" => %{"code" => "credential_already_exists"}
           }

    invalid =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
        "provider" => "unsupported",
        "name" => "primary",
        "values" => %{"api_key" => "private"}
      })

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_credential"}}

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
      |> put_req_header("x-csrf-token", "invalid")
      |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
        "provider" => "google",
        "name" => "primary",
        "values" => %{"api_key" => "private"}
      })
    end

    anonymous = https_get("/admin/api/tenants/#{@tenant_key}/services")

    assert json_response(anonymous, 401) == %{
             "error" => %{"code" => "operator_session_required"}
           }
  end

  test "filters malformed credential values before validation logs them" do
    authenticated = authenticate()
    csrf = admin_csrf(authenticated)
    nested_secret = "synthetic-private-value"
    scalar_secret = "synthetic-scalar-private-value"

    log =
      capture_log([level: :debug], fn ->
        for values <- [%{"apiKey" => nested_secret}, scalar_secret] do
          response =
            authenticated
            |> recycle()
            |> put_req_header("x-csrf-token", csrf)
            |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
              "provider" => "google",
              "name" => "primary",
              "values" => values
            })

          assert json_response(response, 422) == %{
                   "error" => %{"code" => "invalid_credential"}
                 }
        end
      end)

    refute log =~ nested_secret
    refute log =~ scalar_secret
    assert log =~ ~s("values" => "[FILTERED]")
  end

  defp tenant do
    %Tenant{
      key: @tenant_key,
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
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

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp configure_login_repository do
    update_calls(:operator_login_challenge_repository, {
      Vxpipe.Console.Test.OperatorLoginChallengeRepository,
      {self(), :ok}
    })
  end

  defp configure_admin_repository(result) do
    update_calls(:admin_repository, {Vxpipe.Console.Test.AdminRepository, {self(), result}})
  end

  defp configure_credential_repository(result) do
    update_calls(:provider_credential_repository, {
      Vxpipe.Console.Test.OperatorCredentialRepository,
      {self(), result}
    })
  end

  defp update_calls(key, value) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.put(settings, key, value))
  end
end
