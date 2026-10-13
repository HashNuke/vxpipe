defmodule Vxpipe.Console.UserSessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.UserSession

  defmodule Backend do
    def authenticate("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      do: {:ok, %{user_public_id: "user-1"}}

    def authenticate(_), do: {:error, :invalid_session}
  end

  test "stores only an opaque token and rechecks the backend on every fetch" do
    conn =
      Plug.Test.conn(:get, "/admin")
      |> Plug.Test.init_test_session(%{})
      |> UserSession.put(String.duplicate("a", 32))

    assert Plug.Conn.get_session(conn, "vxpipe_user_session") == String.duplicate("a", 32)
    assert {:ok, %{user_public_id: "user-1"}} = UserSession.fetch(conn, backend: Backend)

    assert UserSession.fetch_session(%{"vxpipe_user_session" => String.duplicate("b", 32)},
             backend: Backend
           ) ==
             {:error, :invalid_session}
  end

  test "a missing or malformed token is never authenticated" do
    assert UserSession.fetch_session(%{}, backend: Backend) == {:error, :invalid_session}

    assert UserSession.fetch_session(%{"vxpipe_user_session" => %{}}, backend: Backend) ==
             {:error, :invalid_session}
  end
end
