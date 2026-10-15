defmodule Vxpipe.Console.ProductCallReadsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Console.Test.{FakeUserIdentity, NavigationIdentity}
  @endpoint Vxpipe.Console.Endpoint
  @base "/tenants/AAAAAAAAAAAAAAAA/calls"
  @canonical [
    @base,
    @base <> "/spec-options",
    @base <> "/call",
    @base <> "/call/inspection",
    @base <> "/call/details/publication",
    @base <> "/call/recordings/artifact"
  ]
  @legacy [
    "/admin/api" <> @base,
    "/admin/api" <> @base <> "/spec-options",
    "/admin/api" <> @base <> "/call",
    @base <> "/call/inspection",
    @base <> "/call/details/publication",
    @base <> "/call/recordings/artifact"
  ]

  setup do
    for key <- [:user_identity_backend, :navigation_test_principal, :telephony_host] do
      previous = Application.fetch_env(:vxpipe_console, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:vxpipe_console, key, value)
          :error -> Application.delete_env(:vxpipe_console, key)
        end
      end)
    end

    Application.put_env(:vxpipe_console, :user_identity_backend, NavigationIdentity)
    :ok
  end

  test "every canonical and legacy read rejects explicit credentials before session fallback" do
    auth = login()

    for path <- Enum.map(@canonical, &("/api" <> &1)) ++ @legacy do
      conn =
        auth |> recycle() |> put_req_header("authorization", "Bearer synthetic-key") |> get(path)

      assert json_response(conn, 401) == %{"error" => %{"code" => "session_required"}}
    end
  end

  test "canonical reads require a session, actual tenant permission and an allowed host" do
    auth = login()

    denied = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    Application.put_env(:vxpipe_console, :navigation_test_principal, {:ok, denied})
    Application.put_env(:vxpipe_console, :telephony_host, "carrier.example")

    for path <- Enum.map(@canonical, &("/api" <> &1)) do
      assert build_conn() |> get("https://localhost" <> path) |> json_response(401)
      assert auth |> recycle() |> get(path) |> json_response(403)
      assert build_conn() |> get("http://public.example" <> path) |> response(404)
      assert build_conn() |> get("https://carrier.example" <> path) |> response(404)
    end
  end

  defp login do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end
end
