defmodule Vxpipe.Console.AdminTelnyxConnectionEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Console.Test.FakeUserIdentity

  alias Vxpipe.Persistence.{
    AdminStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore
  }

  @endpoint Vxpipe.Console.Endpoint

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    original = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original)

      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    {:ok, keyring} = CredentialKeyring.new("api", %{"api" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      admin_repository: {AdminStore, Repo}
    ]

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(original, options))
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    {:ok, tenant, issued} = Administration.bootstrap_tenant("API phone tenant", [:admin], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other API tenant", [:admin], options)

    {:ok, credential} =
      ProviderCredentials.provision(
        :platform,
        "telnyx",
        "telnyx",
        "api_key",
        %{
          "api_key" => "synthetic-http-application-secret",
          "public_key" => Base.encode64(<<1::256>>)
        },
        options
      )

    %{
      tenant: tenant,
      other: other,
      issued: issued,
      credential: credential,
      options: options,
      path: "/api/tenants/#{tenant.key}/telnyx-connection"
    }
  end

  test "platform and tenant settings save and reopen with no credential payload", data do
    auth = authenticate()
    token = csrf(auth)

    platform =
      write(
        auth,
        :patch,
        "/api/platform/telnyx-connection",
        %{"application_id" => "shared-application"},
        token
      )

    assert %{"platform_application_id" => "shared-application", "applications" => []} =
             json_response(platform, 200)

    refute platform.resp_body =~ "synthetic-http-application-secret"

    saved = write(auth, :patch, data.path, %{"application_id" => nil}, token)

    assert %{
             "applications" => [
               %{
                 "id" => id,
                 "provider_connection_id" => nil,
                 "effective_application_id" => "shared-application",
                 "source" => "platform"
               }
             ],
             "webhook_urls" => %{"platform" => platform_url, "tenant" => tenant_url}
           } = json_response(saved, 200)

    assert platform_url =~ "/webhooks/platform/telnyx"
    assert tenant_url =~ data.tenant.key

    assert json_response(get(recycle(auth), "https://localhost#{data.path}"), 200) ==
             json_response(saved, 200)

    updated =
      write(
        auth,
        :patch,
        data.path,
        %{
          "service_id" => id,
          "application_id" => "tenant-app",
          "credentials" => %{
            "api_key" => "tenant-http-private",
            "public_key" => Base.encode64(<<1::256>>)
          }
        },
        token
      )

    assert %{"credential" => %{"source" => "tenant"}, "applications" => [%{"source" => "tenant"}]} =
             json_response(updated, 200)

    refute updated.resp_body =~ "tenant-http-private"
    refute updated.resp_body =~ Base.encode64(<<1::256>>)

    reset = write(auth, :patch, data.path, %{"credentials" => nil}, token)

    assert %{
             "credential" => %{"source" => "platform"},
             "applications" => [%{"provider_connection_id" => "tenant-app"}]
           } = json_response(reset, 200)
  end

  test "HTTP save failures leave previous settings intact", data do
    auth = authenticate()
    token = csrf(auth)
    initial = write(auth, :patch, data.path, %{"application_id" => "original"}, token)
    assert initial.status == 200

    failed =
      write(
        auth,
        :patch,
        data.path,
        %{
          "service_id" => Vxpipe.Calls.PublicId.uuid(),
          "application_id" => "bad-target",
          "credentials" => %{
            "api_key" => "rolled-back-private",
            "public_key" => Base.encode64(<<1::256>>)
          }
        },
        token
      )

    assert json_response(failed, 404) == %{"error" => %{"code" => "telephony_service_not_found"}}
    assert {:ok, []} = ProviderCredentials.list(data.tenant.key, data.options)
    assert {:ok, current} = TelephonyServices.fetch(data.tenant.key, "telnyx", data.options)
    assert current.provider_connection_id == "original"

    invalid =
      write(
        auth,
        :patch,
        data.path,
        %{"application_id" => "original", "credentials" => %{"public_key" => "not-a-key"}},
        token
      )

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_provider_auth"}}
  end

  test "connection reads and writes require a session and writes require CSRF", data do
    assert build_conn() |> get("https://localhost#{data.path}") |> response(401)
    auth = authenticate()

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      write(auth, :patch, data.path, %{"application_id" => "own"}, nil)
    end

    forbidden =
      build_conn()
      |> put_req_header("authorization", "Bearer #{data.issued.secret}")
      |> get("https://localhost#{data.path}")

    assert forbidden.status == 401
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
    |> recycle()
    |> get("https://localhost/account")
  end

  defp csrf(authenticated) do
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, authenticated.resp_body)
    token
  end

  defp write(authenticated, method, path, body, token) do
    conn =
      authenticated
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})

    conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn

    case method do
      :post -> post(conn, "https://localhost#{path}", body)
      :patch -> patch(conn, "https://localhost#{path}", body)
    end
  end
end
