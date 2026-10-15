defmodule Vxpipe.Console.UserAuthEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import ExUnit.CaptureLog
  require Phoenix.ChannelTest

  @endpoint Vxpipe.Console.Endpoint

  defmodule Backend do
    def status, do: {:ok, :pending_first_run}

    def setup("owner@example.test", "long-password", "long-password", nil),
      do: {:ok, %{token: String.duplicate("x", 43), user: %{public_id: "owner"}}}

    def setup(_, _, _, _), do: {:error, :invalid_password}

    def setup("limited@example.test", _, _, _, address) do
      send(self(), {:setup_address, address})
      {:error, :rate_limited}
    end

    def setup(email, password, confirmation, proof, _address),
      do: setup(email, password, confirmation, proof)

    def login("owner@example.test", "long-password", _address),
      do: {:ok, %{token: String.duplicate("y", 43), user: %{public_id: "owner"}}}

    def login(_, _, _), do: {:error, :invalid_credentials}

    def recover(
          "local-proof",
          "owner@example.test",
          "new-long-password",
          "new-long-password",
          _address
        ),
        do: {:ok, %{token: String.duplicate("r", 43), user: %{public_id: "owner"}}}

    def recover(_, _, _, _, _), do: {:error, :invalid_proof}
    def logout(_), do: :ok

    def authenticate(_token),
      do:
        {:ok,
         %{
           user_public_id: "owner",
           account_kind: :superadmin,
           grants: MapSet.new(["users.read", "diagnostics.read"]),
           assigned_tenants: %{},
           all_tenant_actions: MapSet.new()
         }}

    def list_users(_actor, _filters),
      do:
        {:ok,
         %{
           users: [
             %{
               public_id: "member",
               email: "member@example.test",
               role_public_id: "role-member",
               disabled_at: nil,
               memberships: %{}
             }
           ],
           total: 1
         }}

    def create_user(%{account_kind: :superadmin}, %{email: "new@example.test"}),
      do:
        {:ok,
         %{
           public_id: "new-user",
           email: "new@example.test",
           role_public_id: "role-member",
           disabled_at: nil,
           memberships: %{}
         }}

    def create_user(_, _), do: {:error, :forbidden}
    def reset_password(_, _, _, _), do: {:error, :forbidden}

    def update_account(%{user_public_id: "owner"}, "long-password", "new@example.test", nil, nil),
      do:
        {:ok,
         %{
           public_id: "owner",
           email: "new@example.test",
           role_public_id: "role-superadmin",
           disabled_at: nil,
           memberships: %{}
         }}

    def update_account(_, _, _, _, _), do: {:error, :invalid_credentials}

    def list_roles(%{account_kind: :superadmin}),
      do:
        {:ok,
         [
           %{
             public_id: "role-member",
             name: "Tenant Member",
             description: "",
             kind: :member,
             revision: 1,
             grants: []
           }
         ]}

    def list_roles(actor, filters) do
      with {:ok, roles} <- list_roles(actor) do
        {:ok,
         %{
           roles: roles,
           total: length(roles),
           page: filters.page,
           page_size: filters.page_size,
           total_pages: 1
         }}
      end
    end

    def list_role_options(_actor),
      do: {:ok, [%{public_id: "role-member", name: "Tenant Member", kind: :member}]}

    def get_role(_actor, "role-member"),
      do:
        {:ok,
         %{
           public_id: "role-member",
           name: "Tenant Member",
           description: "",
           kind: :member,
           revision: 1,
           grants: []
         }}

    def affected_user_count(_actor, "role-member"), do: {:ok, 7}

    def update_role(_, "role-member", _attrs), do: {:error, :stale_revision}

    def create_role(%{account_kind: :superadmin}, %{slug: slug, name: "Reviewer"})
        when is_binary(slug),
        do:
          {:ok,
           %{
             public_id: "new-role",
             name: "Reviewer",
             description: "",
             kind: :member,
             revision: 1,
             grants: []
           }}

    def session_details(%{user_public_id: "owner"}),
      do:
        {:ok,
         {%{
            public_id: "owner",
            email: "owner@example.test",
            role_public_id: "role-superadmin",
            disabled_at: nil,
            memberships: %{}
          },
          %{
            public_id: "role-superadmin",
            name: "Superadmin",
            description: "",
            kind: :superadmin,
            revision: 1,
            grants: []
          }}}
  end

  defmodule FailingLogoutBackend do
    def logout(_token), do: {:error, :unavailable}
  end

  setup do
    original = Application.get_env(:vxpipe_console, :user_identity_backend)
    Application.put_env(:vxpipe_console, :user_identity_backend, Backend)

    on_exit(fn ->
      if original,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    :ok
  end

  test "the public status route reports first-run setup" do
    response = get(build_conn(), "https://localhost/auth/api/status")
    assert json_response(response, 200) == %{"status" => "pending_first_run"}
  end

  test "setup, login and local recovery pages load the Console application" do
    for path <- ["/auth/setup", "/auth/login", "/auth/recover"] do
      response = get(build_conn(), "https://localhost#{path}")
      assert html_response(response, 200) =~ ~s(id="admin-root")
      assert html_response(response, 200) =~ ~s(src="/assets/admin.js")
    end
  end

  test "successful setup starts an opaque user session" do
    response =
      post(build_conn(), "https://localhost/auth/api/setup", %{
        "email" => "owner@example.test",
        "password" => "long-password",
        "password_confirmation" => "long-password"
      })

    assert json_response(response, 200) == %{"ok" => true}
    assert Plug.Conn.get_session(response, "vxpipe_user_session") == String.duplicate("x", 43)
  end

  test "local recovery proof accepts a replacement password and starts a named session" do
    response =
      post(build_conn(), "https://localhost/auth/api/recover", %{
        "proof" => "local-proof",
        "email" => "owner@example.test",
        "password" => "new-long-password",
        "password_confirmation" => "new-long-password"
      })

    assert json_response(response, 200) == %{"ok" => true}
    assert Plug.Conn.get_session(response, "vxpipe_user_session") == String.duplicate("r", 43)
    refute response.resp_body =~ "new-long-password"
  end

  test "setup passes the client address and reports throttling as 429" do
    response =
      build_conn()
      |> Map.put(:remote_ip, {192, 0, 2, 18})
      |> post("https://localhost/auth/api/setup", %{
        "email" => "limited@example.test",
        "password" => "long-password",
        "password_confirmation" => "long-password"
      })

    assert json_response(response, 429) == %{"error" => %{"code" => "rate_limited"}}
    assert_received {:setup_address, "192.0.2.18"}
  end

  test "HTTPS login issues a secure browser session cookie" do
    response =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    cookies = Plug.Conn.get_resp_header(response, "set-cookie") |> Enum.join(";")
    assert cookies =~ "secure"
    assert cookies =~ "HttpOnly"
    assert cookies =~ "SameSite=Lax"
  end

  test "bad login does not start a session or echo a password" do
    response =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "wrong-password"
      })

    assert json_response(response, 401) == %{"error" => %{"code" => "invalid_credentials"}}
    refute response.resp_body =~ "wrong-password"
  end

  for {method, path} <- [
        {:get, "/admin/api/users"},
        {:get, "/admin/api/users/00000000-0000-4000-8000-000000000001"},
        {:post, "/admin/api/users"},
        {:patch, "/admin/api/users/00000000-0000-4000-8000-000000000001"},
        {:get, "/admin/api/role-options"},
        {:get, "/admin/api/tenants"},
        {:get, "/admin/api/tenants/AAAAAAAAAAAAAAAA/providers"},
        {:get, "/admin/api/tenants/AAAAAAAAAAAAAAAA/providers/google/models"},
        {:get, "/admin/api/tenants/AAAAAAAAAAAAAAAA/call-specs"},
        {:get, "/admin/api/tenants/AAAAAAAAAAAAAAAA/call-specs/example"},
        {:post, "/admin/api/tenants/AAAAAAAAAAAAAAAA/call-specs"},
        {:put, "/admin/api/tenants/AAAAAAAAAAAAAAAA/call-specs/example"},
        {:post, "/admin/api/tenants/AAAAAAAAAAAAAAAA/call-specs/example/revisions/1/publish"}
      ] do
    test "legacy product alias #{method} #{path} rejects explicit credentials before parsing" do
      signed_in =
        post(build_conn(), "https://localhost/auth/api/login", %{
          "email" => "owner@example.test",
          "password" => "long-password"
        })

      for authorization <- ["Basic invalid", "Bearer revoked-key"] do
        response =
          signed_in
          |> recycle()
          |> Plug.Conn.put_req_header("authorization", authorization)
          |> Plug.Conn.put_req_header("content-type", "application/json")
          |> dispatch(@endpoint, unquote(method), "https://localhost" <> unquote(path), "{")

        assert json_response(response, 401) == %{"error" => %{"code" => "session_required"}}
      end
    end
  end

  test "a named session reads the server-paginated user directory" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    directory = signed_in |> recycle() |> get("https://localhost/admin/api/users?page=1")

    assert %{"users" => [%{"email" => "member@example.test"}], "pagination" => %{"total" => 1}} =
             json_response(directory, 200)
  end

  test "session details use the named account and current role" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    session = signed_in |> recycle() |> get("https://localhost/admin/api/session")

    assert %{"user" => %{"email" => "owner@example.test"}, "role" => %{"kind" => "superadmin"}} =
             json_response(session, 200)
  end

  test "diagnostics accepts a named user session across HTTP and socket connections" do
    original = Application.fetch_env!(:vxpipe_console, :diagnostics)
    Application.put_env(:vxpipe_console, :diagnostics, Keyword.put(original, :enabled, true))
    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, original) end)

    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    assert html_response(
             signed_in |> recycle() |> get("https://localhost/admin/diagnostics"),
             200
           ) =~
             "Vxpipe diagnostics"

    assert {:ok, %Phoenix.Socket{}} =
             Phoenix.ChannelTest.connect(Vxpipe.Console.DiagnosticsSocket, %{},
               connect_info: %{session: Plug.Conn.get_session(signed_in)}
             )
  end

  test "account writes use the actor and report target denial" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    created =
      signed_in
      |> recycle()
      |> post("https://localhost/admin/api/users", %{
        "email" => "new@example.test",
        "password" => "some long password",
        "password_confirmation" => "some long password",
        "role_id" => "00000000-0000-4000-8000-000000000001",
        "memberships" => []
      })

    assert %{"user" => %{"id" => "new-user"}} = json_response(created, 201)

    denied =
      signed_in
      |> recycle()
      |> post("https://localhost/admin/api/users/owner/reset-password", %{
        "password" => "replacement password",
        "password_confirmation" => "replacement password"
      })

    assert json_response(denied, 403) == %{"error" => %{"code" => "forbidden"}}
  end

  test "own account email change requires the current password" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    changed =
      signed_in
      |> recycle()
      |> patch("https://localhost/admin/api/account", %{
        "email" => "new@example.test",
        "current_password" => "long-password"
      })

    assert %{"user" => %{"email" => "new@example.test"}} = json_response(changed, 200)

    denied =
      signed_in
      |> recycle()
      |> patch("https://localhost/admin/api/account", %{
        "email" => "new@example.test",
        "current_password" => "wrong-password"
      })

    assert json_response(denied, 401) == %{"error" => %{"code" => "invalid_credentials"}}
  end

  test "logout failure retains the session and reports unavailable" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    Application.put_env(:vxpipe_console, :user_identity_backend, FailingLogoutBackend)
    response = signed_in |> recycle() |> post("https://localhost/auth/logout")

    assert json_response(response, 503) == %{"error" => %{"code" => "unavailable"}}
    assert Plug.Conn.get_session(response, "vxpipe_user_session") == String.duplicate("y", 43)
  end

  test "role listing and creation use the authenticated actor" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    assert %{"roles" => [%{"id" => "role-member"}]} =
             signed_in
             |> recycle()
             |> get("https://localhost/admin/api/roles")
             |> json_response(200)

    created =
      signed_in
      |> recycle()
      |> post("https://localhost/admin/api/roles", %{
        "name" => "Reviewer",
        "description" => "",
        "grants" => []
      })

    assert %{"role" => %{"id" => "new-role"} = role} = json_response(created, 201)
    refute Map.has_key?(role, "description")
  end

  test "role filter options are available to user-directory readers" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    response = signed_in |> recycle() |> get("https://localhost/admin/api/role-options")
    assert %{"roles" => [%{"id" => "role-member"}]} = json_response(response, 200)
  end

  test "role details report the persisted number of affected users" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    response = signed_in |> recycle() |> get("https://localhost/admin/api/roles/role-member")
    assert %{"affected_users" => 7} = json_response(response, 200)
  end

  test "role revision conflicts return a conflict response" do
    signed_in =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "owner@example.test",
        "password" => "long-password"
      })

    response =
      signed_in
      |> recycle()
      |> patch("https://localhost/admin/api/roles/role-member", %{
        "name" => "Tenant Member",
        "description" => "",
        "grants" => [],
        "expected_revision" => 1
      })

    assert json_response(response, 409) == %{"error" => %{"code" => "stale"}}
  end

  test "operator setup proof is redacted from request logs" do
    proof = "secret-setup-proof-12345"

    log =
      capture_log(fn ->
        post(build_conn(), "https://localhost/auth/api/setup", %{
          "email" => "owner@example.test",
          "password" => "wrong",
          "password_confirmation" => "wrong",
          "proof" => proof
        })
      end)

    refute log =~ proof
    assert log =~ ~s("proof" => "[FILTERED]")
  end
end
