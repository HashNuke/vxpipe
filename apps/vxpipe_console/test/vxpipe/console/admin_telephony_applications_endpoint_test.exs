defmodule Vxpipe.Console.AdminTelephonyApplicationsEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}

  alias Vxpipe.Persistence.{
    AdminStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore
  }

  @endpoint Vxpipe.Console.Endpoint
  @token "phone-application-operator"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    original = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
    end)

    {:ok, keyring} = CredentialKeyring.new("api", %{"api" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      admin_repository: {AdminStore, Repo},
      operator_login_challenge_repository:
        {Vxpipe.Console.Test.OperatorLoginChallengeRepository, {self(), :ok}}
    ]

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(original, options))

    Application.put_env(
      :vxpipe_console,
      :operator_login_secret,
      String.duplicate("synthetic-phone-login-", 4)
    )

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
      path: "/admin/api/tenants/#{tenant.key}/telephony-applications"
    }
  end

  test "operator HTTP create, reload and edit use a safe tenant application contract", data do
    authenticated = authenticate()
    csrf = csrf(authenticated)

    created =
      write(
        authenticated,
        :post,
        data.path,
        %{"name" => "support", "provider_connection_id" => "phone-application"},
        csrf
      )

    assert %{"application" => %{"id" => id, "name" => "support"}} = json_response(created, 201)
    assert {:ok, snapshot} = TelephonyServices.resolve(data.tenant.key, "support", data.options)
    assert snapshot.service.credential_owner == :platform

    listing = authenticated |> recycle() |> get("https://localhost#{data.path}")

    assert %{"applications" => [%{"id" => ^id, "published_routes" => []}], "truncated" => false} =
             json_response(listing, 200)

    refute listing.resp_body =~ "synthetic-http-application-secret"
    refute listing.resp_body =~ "credential_id"
    refute listing.resp_body =~ "public_key"

    updated =
      write(
        authenticated,
        :patch,
        "#{data.path}/#{id}",
        %{"provider_connection_id" => "updated-application", "outbound_number" => "+15550002000"},
        csrf
      )

    assert %{"application" => %{"id" => ^id, "provider_connection_id" => "updated-application"}} =
             json_response(updated, 200)

    foreign = "/admin/api/tenants/#{data.other.key}/telephony-applications/#{id}"

    assert json_response(
             write(authenticated, :patch, foreign, %{"outbound_number" => nil}, csrf),
             404
           ) == %{"error" => %{"code" => "telephony_service_not_found"}}
  end

  test "anonymous and tenant API keys cannot manage applications and every write requires CSRF",
       data do
    assert build_conn() |> get("https://localhost#{data.path}") |> response(401)

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{data.issued.secret}")
      |> get("https://localhost#{data.path}")

    assert response.status == 401
    authenticated = authenticate()
    body = %{"name" => "support", "provider_connection_id" => "phone-application"}

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      write(authenticated, :post, data.path, body, nil)
    end

    created = write(authenticated, :post, data.path, body, csrf(authenticated))
    id = json_response(created, 201)["application"]["id"]

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      write(authenticated, :patch, "#{data.path}/#{id}", %{"outbound_number" => nil}, nil)
    end
  end

  test "invalid, conflicting and unavailable configuration has bounded recoverable errors",
       data do
    authenticated = authenticate()
    csrf = csrf(authenticated)
    body = %{"name" => "support", "provider_connection_id" => "phone-application"}

    for field <- ["provider", "credential_id", "public_key", "tenant_key", "ingress_key"] do
      assert json_response(
               write(authenticated, :post, data.path, Map.put(body, field, "not-allowed"), csrf),
               422
             ) == %{"error" => %{"code" => "invalid_telephony_service"}}
    end

    created = write(authenticated, :post, data.path, body, csrf)
    id = json_response(created, 201)["application"]["id"]

    assert json_response(write(authenticated, :post, data.path, body, csrf), 409) == %{
             "error" => %{"code" => "telephony_service_conflict"}
           }

    assert :ok = ProviderCredentials.delete(:platform, data.credential.id, data.options)

    assert json_response(
             write(
               authenticated,
               :patch,
               "#{data.path}/#{id}",
               %{"outbound_number" => nil},
               csrf
             ),
             422
           ) == %{"error" => %{"code" => "provider_credential_unavailable"}}
  end

  defp authenticate do
    form = get(build_conn(), "https://localhost/auth/login-token/#{@token}")
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, form.resp_body)

    form
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => token,
      "operator" => %{"token" => @token, "code" => "01234567"}
    })
    |> recycle()
    |> get("https://localhost/admin")
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
