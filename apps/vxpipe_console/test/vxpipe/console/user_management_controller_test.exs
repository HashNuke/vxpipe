defmodule Vxpipe.Console.UserManagementControllerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.UserManagementController

  setup do
    original = Application.get_env(:vxpipe_console, :user_identity_backend)
    Application.put_env(:vxpipe_console, :user_identity_backend, __MODULE__)

    on_exit(fn ->
      if original,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)
  end

  test "invalid account-directory queries remain client errors on the browser route" do
    for reason <- [:page_out_of_range, :invalid_pagination, :invalid_search, :invalid_role_filter] do
      conn =
        Plug.Test.conn(:get, "/api/users")
        |> Plug.Conn.assign(:user_principal, reason)
        |> UserManagementController.index(%{})

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"error" => %{"code" => Atom.to_string(reason)}}
    end
  end

  def list_users(reason, _filters), do: {:error, reason}
end
