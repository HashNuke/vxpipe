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
    configure_credential_validator(:ok)
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
      secret_hints: %{"api_key" => "8c4a"},
      last_validated_at: ~U[2026-09-17 01:55:00Z],
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
                 "credential_preview" => [
                   %{"format" => "last_four", "label" => "API key", "last_four" => "8c4a"}
                 ],
                 "last_validated_at" => "2026-09-17T01:55:00Z",
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
          {"rime", %{"api_key" => "rime-private"}, "api_key", %{"api_key" => "rime-private"}},
          {"google", %{"api_key" => "google-private"}, "api_key",
           %{"api_key" => "google-private"}},
          {"deepgram", %{"api_key" => "deepgram-private"}, "api_key",
           %{"api_key" => "deepgram-private"}},
          {"zenmux", %{"api_key" => "zenmux-private"}, "api_key",
           %{"api_key" => "zenmux-private"}},
          {"telnyx", %{"api_key" => "telnyx-private"}, "api_key",
           %{"api_key" => "telnyx-private"}},
          {"telnyx", %{"api_key" => "telnyx-private", "public_key" => Base.encode64(<<1::256>>)},
           "api_key",
           %{"api_key" => "telnyx-private", "public_key" => Base.encode64(<<1::256>>)}},
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
        name: provider,
        auth_kind: expected_kind,
        last_validated_at: ~U[2026-09-18 04:00:00Z],
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
              "values" => values
            })

          assert %{
                   "credential" => %{
                     "id" => ^returned_id,
                     "provider" => ^provider,
                     "name" => ^provider,
                     "auth_kind" => ^expected_kind,
                     "last_validated_at" => "2026-09-18T04:00:00Z",
                     "status" => "active"
                   }
                 } = json_response(response, 201)

          for secret <- Map.values(values), do: refute(response.resp_body =~ secret)
        end)

      for secret <- Map.values(values), do: refute(log =~ secret)
      assert_received {:operator_credential_created, created, ^expected_payload}

      assert_received {:operator_credential_validated, ^provider, ^expected_kind,
                       ^expected_payload}

      assert created.tenant_key == @tenant_key
      assert created.provider == provider
      assert created.name == provider
    end
  end

  test "updates an exact credential and returns only safe preview metadata" do
    returned = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: @tenant_key,
      provider: "twilio",
      name: "twilio",
      auth_kind: "account_sid_auth_token",
      version: 2,
      secret_hints: %{"account_sid" => "1111"},
      inserted_at: ~U[2026-09-17 02:00:00Z],
      updated_at: ~U[2026-09-18 02:00:00Z]
    }

    configure_credential_repository({:ok, returned})
    authenticated = authenticate()
    csrf = admin_csrf(authenticated)
    returned_id = returned.id

    response =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> patch(
        "https://localhost/admin/api/tenants/#{@tenant_key}/credentials/#{returned.id}",
        %{
          "provider" => "twilio",
          "values" => %{
            "account_sid" => "AC11111111111111111111111111111111",
            "auth_token" => "replacement-private"
          }
        }
      )

    assert %{
             "credential" => %{
               "id" => ^returned_id,
               "name" => "twilio",
               "credential_preview" => [
                 %{"format" => "last_four", "label" => "Account SID", "last_four" => "1111"},
                 %{"format" => "masked", "label" => "Auth token"}
               ]
             }
           } = json_response(response, 200)

    refute response.resp_body =~ "replacement-private"

    assert_received {:operator_credential_replaced, @tenant_key, credential_id, "twilio",
                     "account_sid_auth_token", _payload, %DateTime{}}

    assert credential_id == returned.id
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

  test "does not store credentials rejected by the provider" do
    configure_credential_validator({:error, :provider_credential_rejected})
    authenticated = authenticate()
    csrf = admin_csrf(authenticated)

    response =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
        "provider" => "google",
        "values" => %{"api_key" => "rejected-private"}
      })

    assert json_response(response, 422) == %{
             "error" => %{"code" => "credential_rejected"}
           }

    refute_received {:operator_credential_created, _, _}
  end

  test "creates a named platform credential through the protected operator endpoint" do
    credential = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      owner: :platform,
      tenant_key: nil,
      provider: "google",
      name: "shared-model",
      auth_kind: "api_key"
    }

    configure_credential_repository({:ok, credential})

    body = %{
      "provider" => "google",
      "name" => "shared-model",
      "values" => %{"api_key" => "platform-example-key"}
    }

    anonymous = post(build_conn(), "https://localhost/admin/api/platform/credentials", body)
    assert anonymous.status in [401, 403]
    refute_received {:operator_credential_created, _, _}

    authenticated = authenticate() |> recycle() |> https_get("/admin")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, authenticated.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
      |> post("https://localhost/admin/api/platform/credentials", body)
    end

    refute_received {:operator_credential_created, _, _}

    response =
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/platform/credentials", body)

    assert %{"credential" => %{"name" => "shared-model", "id" => id}} =
             json_response(response, 201)

    assert id == credential.id
    refute response.resp_body =~ "platform-example-key"

    assert_received {:operator_credential_created,
                     %ProviderCredential{owner: :platform, tenant_key: nil, name: "shared-model"},
                     _payload}
  end

  test "lists platform and inherited bindings using operator authority" do
    previous_origin = Application.fetch_env!(:vxpipe_console, :service_public_origin)

    Application.put_env(
      :vxpipe_console,
      :service_public_origin,
      "https://callbacks.example.test/voice"
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :service_public_origin, previous_origin)
    end)

    binding = %{
      provider: "google",
      name: "shared-model",
      source: :platform,
      status: :connected,
      credential_id: "shared-id",
      platform_available: true,
      saved_fields: ["api_key"],
      last_validated_at: nil
    }

    configure_credential_repository(
      {:ok, %{tenant: %{key: @tenant_key, name: "Example tenant"}, bindings: [binding]}}
    )

    conn =
      authenticate()
      |> recycle()
      |> https_get("/admin/api/tenants/#{@tenant_key}/service-bindings")

    assert %{"bindings" => [%{"source" => "platform", "name" => "shared-model"}]} =
             json_response(conn, 200)

    assert_received {:operator_bindings_requested, @tenant_key}

    assert json_response(conn, 200)["webhook_urls"] == %{
             "platform" => "https://callbacks.example.test/voice/webhooks/platform/telnyx",
             "tenant" =>
               "https://callbacks.example.test/voice/webhooks/tenants/#{@tenant_key}/telnyx"
           }

    refute conn.resp_body =~ "payload"

    configure_credential_repository({:ok, %{tenant: nil, bindings: [binding]}})

    conn = authenticate() |> recycle() |> https_get("/admin/api/platform/services")

    assert %{"tenant" => nil, "bindings" => [%{"source" => "platform"}]} =
             json_response(conn, 200)

    assert_received {:operator_bindings_requested, :platform}

    assert json_response(conn, 200)["webhook_urls"] == %{
             "platform" => "https://callbacks.example.test/voice/webhooks/platform/telnyx",
             "tenant" => nil
           }

    assert https_get("/admin/api/platform/services").status == 401
    refute_received {:operator_bindings_requested, _}
  end

  test "platform replacement requires CSRF and preserves exact credential identity" do
    credential = %ProviderCredential{
      id: "shared-id",
      owner: :platform,
      tenant_key: nil,
      provider: "google",
      name: "shared-model",
      auth_kind: "api_key"
    }

    configure_credential_repository({:ok, credential})
    authenticated = authenticate() |> recycle() |> https_get("/admin")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, authenticated.resp_body)

    conn =
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})

    body = %{"provider" => "google", "values" => %{"api_key" => "platform-replacement"}}

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      patch(conn, "https://localhost/admin/api/platform/credentials/shared-id", body)
    end

    refute_received {:operator_credential_replaced, _, _, _, _, _, _}

    updated =
      conn
      |> put_req_header("x-csrf-token", csrf)
      |> patch("https://localhost/admin/api/platform/credentials/shared-id", body)

    assert %{"credential" => %{"id" => "shared-id", "name" => "shared-model"}} =
             json_response(updated, 200)

    refute updated.resp_body =~ "platform-replacement"

    assert_received {:operator_credential_replaced, :platform, "shared-id", "google", "api_key",
                     _, _}
  end

  test "credential deletion requires an operator session and CSRF and preserves exact ownership" do
    for {scope, prefix} <- [{@tenant_key, "tenants/#{@tenant_key}"}, {:platform, "platform"}] do
      path = "https://localhost/admin/api/#{prefix}/credentials/exact-id"
      configure_credential_repository(:ok)
      assert json_response(delete(build_conn(), path), 401)
      refute_received {:operator_credential_deleted, _, _}

      authenticated = authenticate() |> recycle() |> https_get("/admin")

      [_, csrf] =
        Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, authenticated.resp_body)

      conn =
        authenticated
        |> recycle()
        |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn -> delete(conn, path) end
      refute_received {:operator_credential_deleted, _, _}
      response = conn |> put_req_header("x-csrf-token", csrf) |> delete(path)
      assert response.status == 204
      assert response.resp_body == ""
      assert_received {:operator_credential_deleted, ^scope, "exact-id"}

      for {reason, status, code} <- [
            {:invalid_provider_credential_id, 422, "invalid_credential"},
            {:provider_credential_not_found, 404, "provider_credential_not_found"},
            {:provider_credential_in_use, 409, "provider_credential_in_use"},
            {{:storage_failed, "private-detail"}, 503, "credential_store_unavailable"}
          ] do
        configure_credential_repository({:error, reason})
        failed = conn |> put_req_header("x-csrf-token", csrf) |> delete(path)
        assert json_response(failed, status) == %{"error" => %{"code" => code}}
        refute failed.resp_body =~ "private-detail"
        assert_received {:operator_credential_deleted, ^scope, "exact-id"}
      end
    end
  end

  test "tenant credential creation preserves an explicit named binding" do
    returned = %ProviderCredential{
      id: "named-id",
      tenant_key: @tenant_key,
      provider: "google",
      name: "named-model",
      auth_kind: "api_key"
    }

    configure_credential_repository({:ok, returned})
    authenticated = authenticate()
    csrf = admin_csrf(authenticated)

    response =
      authenticated
      |> recycle()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost/admin/api/tenants/#{@tenant_key}/credentials", %{
        "provider" => "google",
        "name" => "named-model",
        "values" => %{"api_key" => "synthetic-named"}
      })

    assert json_response(response, 201)["credential"]["name"] == "named-model"

    assert_received {:operator_credential_created,
                     %{name: "named-model", tenant_key: @tenant_key}, _}
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

  defp configure_credential_validator(result) do
    update_calls(:provider_credential_validator, {
      Vxpipe.Console.Test.OperatorCredentialValidator,
      {self(), result}
    })
  end

  defp update_calls(key, value) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.put(settings, key, value))
  end
end
