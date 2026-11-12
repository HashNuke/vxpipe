defmodule Vxpipe.Console.OAuthBrowserTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Vxpipe.Console.RequireUser
  alias Vxpipe.Identity.Principal
  @endpoint Vxpipe.Console.Endpoint
  @id Base.url_encode64(<<1::256>>, padding: false)
  @token String.duplicate("s", 43)
  @resource "https://localhost/mcp"

  setup do
    previous =
      for key <- [:oauth, :user_identity_backend],
          do: {key, Application.get_env(:vxpipe_console, key)}

    Application.put_env(:vxpipe_console, :oauth,
      enabled: true,
      issuer: "https://localhost",
      resource: @resource,
      allowed_hosts: ["localhost"],
      backend: __MODULE__
    )

    Application.put_env(:vxpipe_console, :user_identity_backend, __MODULE__)

    on_exit(fn ->
      for {key, value} <- previous do
        if value == nil,
          do: Application.delete_env(:vxpipe_console, key),
          else: Application.put_env(:vxpipe_console, key, value)
      end
    end)

    :ok
  end

  test "authorization survives login with only an opaque return path and browser binding" do
    started = get(build_conn(), authorization_url())
    assert redirected_to(started) == "/oauth/authorize/#{@id}"
    binding = get_session(started, "vxpipe_oauth_browser")
    assert byte_size(binding) == 43
    assert_received {:begin, %{"state" => "private-state"}, @resource, ^binding}
    login = started |> recycle() |> get("https://localhost/oauth/authorize/#{@id}")
    assert redirected_to(login) == "/auth/login"
    assert get_session(login, "vxpipe_return_path") == "/oauth/authorize/#{@id}"

    signed_in =
      login
      |> recycle()
      |> post("https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "password"
      })

    assert get_session(signed_in, "vxpipe_oauth_browser") == binding
    consent = signed_in |> recycle() |> get("https://localhost/oauth/authorize/#{@id}")
    assert html_response(consent, 200) =~ "Connect Research client"
    assert html_response(consent, 200) =~ "https://client.example/oauth/client.json"
    assert get_resp_header(consent, "cache-control") == ["private, no-store"]
    assert get_resp_header(consent, "referrer-policy") == ["no-referrer"]
    assert RequireUser.allowed_path?(principal(), "/oauth/authorize/#{@id}")

    for path <- [
          "/oauth/authorize",
          "/oauth/authorize/#{@id}?next=evil",
          "/oauth/authorize/#{@id}#fragment",
          "/oauth//authorize/#{@id}",
          "/oauth/authorize/nope"
        ] do
      refute RequireUser.allowed_path?(principal(), path)
    end
  end

  test "consent mounts the reviewed UI with real branding and authority" do
    body = signed_consent() |> html_response(200)
    assert body =~ ~s(src="/assets/oauth.js")
    assert body =~ ~s(id="oauth-root")
    assert body =~ "https://client.example/logo.png"
    assert body =~ "https://client.example/about"
    assert body =~ "owner@example.test"
    assert body =~ "2592000"
    assert body =~ "tenants.read"
  end

  test "consent loads the deployment's versioned assets instead of old unversioned URLs" do
    manifest_path = "priv/static/assets/consent-test-#{System.unique_integer([:positive])}.json"
    manifest_file = Application.app_dir(:vxpipe_console, manifest_path)
    previous = @endpoint.config(:cache_static_manifest)

    latest = %{
      "assets/oauth.js" => "assets/oauth-current.js",
      "assets/oauth.css" => "assets/oauth-current.css",
      "assets/admin-ui.css" => "assets/admin-ui-current.css"
    }

    File.mkdir_p!(Path.dirname(manifest_file))
    File.write!(manifest_file, JSON.encode!(%{latest: latest, digests: %{}}))
    Phoenix.Config.put(@endpoint, :cache_static_manifest, manifest_path)
    @endpoint.config_change([], [])

    on_exit(fn ->
      Phoenix.Config.put(@endpoint, :cache_static_manifest, previous)
      @endpoint.config_change([], [])
      File.rm!(manifest_file)
    end)

    body = signed_consent() |> html_response(200)
    assert body =~ ~s(src="/assets/oauth-current.js?vsn=d")
    assert body =~ ~s(href="/assets/oauth-current.css?vsn=d")
    assert body =~ ~s(href="/assets/admin-ui-current.css?vsn=d")
    refute body =~ ~s(src="/assets/oauth.js")
  end

  test "authorization uses the current installation host and resource" do
    options = Application.fetch_env!(:vxpipe_console, :oauth)

    Application.put_env(
      :vxpipe_console,
      :oauth,
      Keyword.put(options, :public_url_provider, __MODULE__)
    )

    for origin <- ["https://first.example.test", "https://second.example.test"] do
      Process.put(:installation_origin, {:ok, origin})

      url =
        String.replace(authorization_url(), "https://localhost", origin)
        |> String.replace(URI.encode_www_form(@resource), URI.encode_www_form(origin <> "/mcp"))

      assert build_conn() |> get(url) |> redirected_to() == "/oauth/authorize/#{@id}"
      assert_received {:begin, _, resource, _}
      assert resource == origin <> "/mcp"
    end

    assert build_conn() |> get(authorization_url()) |> response(403)
    Process.put(:installation_origin, {:error, :unavailable})
    assert build_conn() |> get(authorization_url()) |> response(503)
  end

  def public_url, do: Process.get(:installation_origin)

  test "approval and denial wait on confirmation with the exact callback link" do
    for {decision, expected} <- [
          {"approve", %{"code" => "secret-code"}},
          {"deny", %{"error" => "access_denied"}}
        ] do
      consent = signed_consent()

      response =
        consent
        |> recycle()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("https://localhost/oauth/authorize/#{@id}", "decision=#{decision}")

      body = html_response(response, 200)
      assert get_resp_header(response, "location") == []
      assert get_resp_header(response, "cache-control") == ["private, no-store"]
      assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
      assert body =~ ~s(data-state="#{if decision == "approve", do: "allowed", else: "denied"}")
      assert body =~ "data-completion="

      [_, destination] =
        Regex.run(~r/<a href="([^"]+)" rel="noreferrer">Back to my app<\/a>/, body)

      callback = destination |> String.replace("&amp;", "&") |> URI.parse()
      assert callback.host == "client.example"

      assert URI.decode_query(callback.query) ==
               Map.merge(
                 %{
                   "existing" => "keep",
                   "state" => "private-state",
                   "iss" => "https://localhost"
                 },
                 expected
               )
    end
  end

  test "native form posts with a privacy-redacted origin still require valid session CSRF" do
    consent = signed_consent()
    [_, csrf] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html_response(consent, 200))
    body = URI.encode_query(%{"decision" => "approve", "_csrf_token" => csrf})

    request =
      consent |> recycle() |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))

    request =
      request
      |> put_req_header("origin", "null")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    assert request |> post("https://localhost/oauth/authorize/#{@id}", body) |> response(200)
    assert_received {:complete, :approve}
    foreign = put_req_header(request, "origin", "https://evil.example")
    assert foreign |> post("https://localhost/oauth/authorize/#{@id}", body) |> response(403)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(request, "https://localhost/oauth/authorize/#{@id}", "decision=approve")
    end

    refute_received {:complete, _}

    assert build_conn()
           |> put_req_header("origin", "null")
           |> get(authorization_url())
           |> response(403)
  end

  test "forged binding and non-session principals cannot complete consent" do
    consent = signed_consent()

    forged =
      consent
      |> recycle()
      |> init_test_session(%{
        "vxpipe_user_session" => @token,
        "vxpipe_oauth_browser" => String.duplicate("z", 43)
      })
      |> get("https://localhost/oauth/authorize/#{@id}")

    assert response(forged, 400)
    assert forged.resp_body =~ ~s(data-state="unavailable")
    assert forged.resp_body =~ ~s(src="/assets/oauth.js")
    Process.put(:oauth_principal, %{principal() | credential_kind: :oauth})
    rejected = consent |> recycle() |> get("https://localhost/oauth/authorize/#{@id}")
    assert response(rejected, 403)
  end

  test "completion failures render a local recovery page without a callback or approval receipt" do
    for {result, status} <- [
          {{:error, :invalid_request}, 400},
          {{:error, :forbidden}, 403},
          {{:error, :unavailable}, 503},
          {{:ok, %{redirect_uri: "javascript:alert(1)", code: "secret-code"}}, 503}
        ] do
      consent = signed_consent()
      Process.put(:oauth_completion_result, result)

      failed =
        consent
        |> recycle()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("https://localhost/oauth/authorize/#{@id}", "decision=approve")

      assert html_response(failed, status) =~ ~s(data-state="unavailable")
      assert get_resp_header(failed, "location") == []
      assert get_resp_header(failed, "cache-control") == ["private, no-store"]
      refute failed.resp_body =~ "secret-code"
      refute failed.resp_body =~ "Access approved"
    end
  end

  test "untrusted origin, host, plaintext transport, and bearer credentials fail closed" do
    for conn <- [
          put_req_header(build_conn(), "origin", "https://evil.example"),
          put_req_header(build_conn(), "authorization", "Bearer secret")
        ] do
      assert conn |> get(authorization_url()) |> response(403)
    end

    assert build_conn()
           |> get(String.replace(authorization_url(), "localhost", "evil.example", global: false))
           |> response(403)

    assert build_conn()
           |> get(String.replace(authorization_url(), "https:", "http:", global: false))
           |> response(403)

    refute_received {:begin, _, _, _}
  end

  test "HTTP development authorization requires a loopback peer, not just a loopback host" do
    options = Application.fetch_env!(:vxpipe_console, :oauth)

    Application.put_env(
      :vxpipe_console,
      :oauth,
      Keyword.merge(options, issuer: "http://localhost", allow_loopback_http: true)
    )

    url = String.replace(authorization_url(), "https:", "http:", global: false)
    remote = %{build_conn() | remote_ip: {198, 51, 100, 9}}
    assert remote |> get(url) |> response(403)
    refute_received {:begin, _, _, _}
    assert build_conn() |> get(url) |> redirected_to() == "/oauth/authorize/#{@id}"
  end

  test "duplicate, unknown and oversized query inputs never reach the backend" do
    for suffix <- [
          "&state=again",
          "&other=unknown",
          "&state%5B%5D=evil",
          "&x=" <> String.duplicate("x", 16_384)
        ] do
      assert build_conn() |> get(authorization_url() <> suffix) |> response(400)
    end

    refute_received {:begin, _, _, _}
  end

  test "decision duplicate inputs and missing CSRF do not issue authorization codes" do
    consent = signed_consent()

    duplicate =
      consent
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("https://localhost/oauth/authorize/#{@id}", "decision=approve&decision=deny")

    assert response(duplicate, 400)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      consent
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("https://localhost/oauth/authorize/#{@id}", "decision=approve")
    end

    refute_received {:complete, _}
  end

  test "decision rejects obsolete presentation flags and duplicate fields before completion" do
    for extra <- [
          "presentation=receipt",
          "presentation=other",
          "presentation=receipt&presentation=receipt"
        ] do
      consent = signed_consent()

      rejected =
        consent
        |> recycle()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("https://localhost/oauth/authorize/#{@id}", "decision=approve&" <> extra)

      assert response(rejected, 400)
      refute_received {:complete, _}
    end
  end

  test "rejected consent submissions log the reason without form values or request identifiers" do
    for {body, reason} <- [
          {"_csrf_token=private-csrf-sentinel", "missing_decision"},
          {"decision=private-decision-sentinel", "invalid_decision"},
          {"decision=approve&unknown=private-extra-sentinel", "unexpected_form_fields"},
          {"decision=approve&decision=deny", "malformed_form"}
        ] do
      consent = signed_consent()

      log =
        capture_log(fn ->
          rejected =
            consent
            |> recycle()
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post("https://localhost/oauth/authorize/#{@id}", body)

          assert response(rejected, 400)
        end)

      assert log =~ "OAuth browser request rejected method=POST status=400 reason=#{reason}"

      for private <- [
            @id,
            "private-csrf-sentinel",
            "private-decision-sentinel",
            "private-extra-sentinel"
          ] do
        refute log =~ private
      end

      refute_received {:complete, _}
    end
  end

  test "rate limiter failures reject locally and sensitive request details are not logged" do
    Process.put(:oauth_limit, {:error, :rate_limited})

    log =
      capture_log(fn ->
        conn = get(build_conn(), authorization_url())
        assert response(conn, 429)
        assert get_resp_header(conn, "retry-after") == ["60"]
      end)

    refute log =~ "private-state"
    refute log =~ "code_challenge"
    refute_received {:begin, _, _, _}
  end

  test "invalid endpoint configuration remains a private local failure" do
    options = Application.fetch_env!(:vxpipe_console, :oauth)
    Application.put_env(:vxpipe_console, :oauth, Keyword.put(options, :issuer, "invalid"))
    conn = get(build_conn(), authorization_url())
    assert response(conn, 503)
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    refute_received {:begin, _, _, _}
  end

  test "connected clients are session-only and revocation is scoped to the current principal" do
    conn = build_conn() |> init_test_session(%{"vxpipe_user_session" => @token})
    listed = get(conn, "https://localhost/api/account/connections")

    assert %{
             "connections" => [
               %{"public_id" => "grant-id", "client_name" => "Research client"} = grant
             ]
           } = json_response(listed, 200)

    refute Map.has_key?(grant, "secret")
    revoked = listed |> recycle() |> delete("https://localhost/api/account/connections/grant-id")
    assert response(revoked, 204)
    assert_received {:revoke, "owner", "grant-id"}

    assert build_conn()
           |> put_req_header("authorization", "Bearer secret")
           |> get("https://localhost/api/account/connections")
           |> response(401)
  end

  def rate_limit(:authorize, "127.0.0.1"), do: Process.get(:oauth_limit, :ok)

  def begin_authorization(params, resource, binding) do
    send(self(), {:begin, params, resource, binding})
    Process.put(:oauth_binding, binding)
    {:ok, @id}
  end

  def consent(@id, binding, %Principal{}) do
    if binding == Process.get(:oauth_binding),
      do:
        {:ok,
         %{
           client_name: "Research client",
           client_uri: "https://client.example/about",
           logo_uri: "https://client.example/logo.png",
           user_email: "owner@example.test",
           grant_lifetime_seconds: 2_592_000,
           client_id: "https://client.example/oauth/client.json",
           redirect_uri: "https://client.example/callback?existing=keep",
           resource: @resource,
           authority: %{
             "grants" => ["tenants.read"],
             "all_tenant_actions" => [],
             "assigned_tenants" => %{}
           }
         }},
      else: {:error, :invalid_request}
  end

  def complete_authorization(@id, binding, %Principal{}, decision) do
    if result = Process.get(:oauth_completion_result) do
      result
    else
      complete_bound_authorization(binding, decision)
    end
  end

  defp complete_bound_authorization(binding, decision) do
    if binding == Process.get(:oauth_binding) do
      send(self(), {:complete, decision})

      {:ok, consent} = consent(@id, binding, principal())

      result = %{
        redirect_uri: "https://client.example/callback?existing=keep",
        state: "private-state",
        receipt: %{
          consent: consent,
          state: if(decision == :approve, do: "allowed", else: "denied"),
          expires_at: if(decision == :approve, do: ~U[2026-12-11 00:00:00Z])
        }
      }

      {:ok,
       Map.merge(
         result,
         if(decision == :approve,
           do: %{code: "secret-code", grant_id: "grant-id"},
           else: %{error: "access_denied"}
         )
       )}
    else
      {:error, :invalid_request}
    end
  end

  def list_grants(%Principal{}),
    do:
      {:ok,
       [
         %{
           public_id: "grant-id",
           client_name: "Research client",
           resource: @resource,
           inserted_at: ~U[2026-10-16 00:00:00Z],
           expires_at: ~U[2026-10-17 00:00:00Z],
           secret: "must-not-leak"
         }
       ]}

  def revoke_grant(principal, id) do
    send(self(), {:revoke, principal.user_public_id, id})
    :ok
  end

  def authenticate(@token), do: {:ok, Process.get(:oauth_principal, principal())}
  def login(_, _, _), do: {:ok, %{token: @token}}

  defp principal,
    do: %Principal{
      user_public_id: "owner",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(),
      assigned_tenants: %{},
      all_tenant_actions: MapSet.new()
    }

  defp authorization_url do
    "https://localhost/oauth/authorize?" <>
      URI.encode_query(%{
        "client_id" => "00000000-0000-4000-8000-000000000001",
        "response_type" => "code",
        "redirect_uri" => "https://client.example/callback?existing=keep",
        "resource" => @resource,
        "state" => "private-state",
        "code_challenge" => @id,
        "code_challenge_method" => "S256"
      })
  end

  defp signed_consent do
    build_conn()
    |> init_test_session(%{"vxpipe_user_session" => @token})
    |> get(authorization_url())
    |> recycle()
    |> get("https://localhost/oauth/authorize/#{@id}")
  end
end
