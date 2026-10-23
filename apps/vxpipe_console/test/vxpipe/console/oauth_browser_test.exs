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

  test "approval and denial preserve registered callback query and state" do
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

      callback = response |> get_resp_header("location") |> hd() |> URI.parse()
      assert callback.host == "client.example"

      assert URI.decode_query(callback.query) ==
               Map.merge(%{"existing" => "keep", "state" => "private-state"}, expected)
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

    assert request |> post("https://localhost/oauth/authorize/#{@id}", body) |> response(302)
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
    Process.put(:oauth_principal, %{principal() | credential_kind: :oauth})
    rejected = consent |> recycle() |> get("https://localhost/oauth/authorize/#{@id}")
    assert response(rejected, 403)
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
    if binding == Process.get(:oauth_binding) do
      send(self(), {:complete, decision})

      result = %{
        redirect_uri: "https://client.example/callback?existing=keep",
        state: "private-state"
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
