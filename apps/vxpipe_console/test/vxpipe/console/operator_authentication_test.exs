defmodule Vxpipe.Console.OperatorAuthenticationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.Principal

  alias Vxpipe.Console.{
    OperatorAuthentication,
    OperatorSession,
    TestOperatorAuthenticator
  }

  import Phoenix.ConnTest, only: [build_conn: 0]

  @tenant_key "tenantkey1234567"

  test "authenticates a calls-scoped operator through the selected boundary" do
    assert {:ok, %Principal{tenant_key: @tenant_key, scopes: scopes}} =
             OperatorAuthentication.authenticate(@tenant_key, "valid-api-key",
               authenticator: {TestOperatorAuthenticator, self()}
             )

    assert MapSet.member?(scopes, :calls)
    assert_receive {:operator_authentication, @tenant_key, "valid-api-key"}
  end

  test "rejects an adapter identity without the calls scope" do
    assert {:error, :insufficient_scope} =
             OperatorAuthentication.authenticate(@tenant_key, "wrong-scope",
               authenticator: {TestOperatorAuthenticator, self()}
             )
  end

  test "stores and restores only the non-secret operator principal" do
    principal = principal()
    api_key_id = principal.api_key_id
    now_unix = 1_788_883_200

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> OperatorSession.put(principal, now_unix: now_unix, max_age_seconds: 3_600)

    assert {:ok, ^principal} = OperatorSession.fetch(conn, now_unix: now_unix + 3_599)

    assert %{
             "api_key_id" => ^api_key_id,
             "expires_at_unix" => 1_788_886_800,
             "scopes" => ["calls"],
             "tenant_key" => @tenant_key
           } = Plug.Conn.get_session(conn, "vxpipe_operator")

    refute inspect(Plug.Conn.get_session(conn)) =~ "valid-api-key"
  end

  test "rejects an expired operator identity" do
    now_unix = 1_788_883_200

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> OperatorSession.put(principal(), now_unix: now_unix, max_age_seconds: 60)

    assert :error = OperatorSession.fetch(conn, now_unix: now_unix + 60)
  end

  test "rejects malformed session identity instead of constructing a principal" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "vxpipe_operator" => %{
          "api_key_id" => "not-an-id",
          "scopes" => ["admin"],
          "tenant_key" => @tenant_key
        }
      })

    assert :error = OperatorSession.fetch(conn)
  end

  test "clears the operator identity" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> OperatorSession.put(principal())
      |> OperatorSession.clear()

    assert :error = OperatorSession.fetch(conn)
    assert Plug.Conn.get_session(conn, "vxpipe_operator") == nil
  end

  defp principal do
    %Principal{
      tenant_key: @tenant_key,
      api_key_id: "01234567-89ab-4cde-8fab-0123456789ab",
      scopes: MapSet.new([:calls])
    }
  end
end
