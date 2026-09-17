defmodule Vxpipe.Console.InstallationOperatorSessionTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [build_conn: 0]

  alias Vxpipe.Console.InstallationOperatorSession

  setup do
    previous_secret = Application.get_env(:vxpipe_console, :operator_login_secret)

    Application.put_env(
      :vxpipe_console,
      :operator_login_secret,
      String.duplicate("session-test-", 6)
    )

    on_exit(fn ->
      if previous_secret,
        do: Application.put_env(:vxpipe_console, :operator_login_secret, previous_secret),
        else: Application.delete_env(:vxpipe_console, :operator_login_secret)
    end)
  end

  test "stores only an installation grant with one absolute twelve-hour expiry" do
    now = 1_789_550_400

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"discard_me" => "old-session"})
      |> InstallationOperatorSession.put(now_unix: now)

    assert {:ok, grant} = InstallationOperatorSession.fetch(conn, now_unix: now + 43_199)
    assert grant.issued_at_unix == now
    assert grant.expires_at_unix == now + 43_200

    assert %{
             "authority" => "installation_operator",
             "issued_at_unix" => ^now,
             "expires_at_unix" => 1_789_593_600,
             "signature" => signature
           } = Plug.Conn.get_session(conn, "vxpipe_installation_operator")

    assert is_binary(signature)

    refute inspect(Plug.Conn.get_session(conn)) =~ "api_key"
  end

  test "rejects grants when the explicit operator secret is unavailable" do
    now = 1_789_550_400

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> InstallationOperatorSession.put(now_unix: now)

    Application.delete_env(:vxpipe_console, :operator_login_secret)

    assert :error = InstallationOperatorSession.fetch(conn, now_unix: now + 1)
  end

  test "rejects the grant at its absolute expiry without extending it" do
    now = 1_789_550_400

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> InstallationOperatorSession.put(now_unix: now)

    assert :error = InstallationOperatorSession.fetch(conn, now_unix: now + 43_200)
    assert :error = InstallationOperatorSession.fetch(conn, now_unix: now + 86_400)
  end

  test "rejects malformed authority and timestamps" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "vxpipe_installation_operator" => %{
          "authority" => "tenant_operator",
          "issued_at_unix" => 1_789_550_400,
          "expires_at_unix" => 1_789_593_600
        }
      })

    assert :error = InstallationOperatorSession.fetch(conn, now_unix: 1_789_550_401)
  end
end
