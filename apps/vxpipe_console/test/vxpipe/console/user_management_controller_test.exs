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

  test "legacy account inputs use shared normalization and public membership keys" do
    params = %{
      "email" => "  new@example.test  ",
      "role_id" => "00000000-0000-4000-8000-000000000001",
      "password" => "long-enough-password",
      "password_confirmation" => "long-enough-password",
      "memberships" => [%{"tenant_id" => "AAAAAAAAAAAAAAAA", "access" => "read_write"}],
      "legacy_ignored_field" => true
    }

    response = account_conn(:post) |> UserManagementController.create(params)
    assert response.status == 201
    assert_received {:created, actor, attrs}
    assert actor == self()
    assert attrs.email == "new@example.test"
    assert attrs.memberships == %{"AAAAAAAAAAAAAAAA" => "read_write"}
    refute Map.has_key?(attrs, :legacy_ignored_field)
  end

  test "legacy full-form updates retain default activation and membership replacement" do
    response =
      account_conn(:patch)
      |> UserManagementController.update(%{"id" => "user-id", "email" => nil, "role_id" => nil})

    assert response.status == 200
    assert_received {:updated, actor, "user-id", attrs}
    assert actor == self()
    assert attrs.disabled == false
    assert attrs.memberships == %{}
    assert Map.get(attrs, :email) == nil
    assert Map.get(attrs, :role_public_id) == nil
  end

  test "legacy account translation rejects invalid public tenant keys before backend writes" do
    response =
      account_conn(:patch)
      |> UserManagementController.update(%{
        "id" => "user-id",
        "enabled" => false,
        "memberships" => [%{"tenant_id" => "database-primary-key", "access" => "read"}]
      })

    assert response.status == 422
    refute_received {:updated, _, _, _}
  end

  defp account_conn(method),
    do: Plug.Test.conn(method, "/admin/api/users") |> Plug.Conn.assign(:user_principal, self())

  def create_user(actor, attrs) do
    send(self(), {:created, actor, attrs})
    {:ok, record()}
  end

  def update_user(actor, id, attrs) do
    send(self(), {:updated, actor, id, attrs})
    {:ok, record()}
  end

  defp record,
    do: %{
      public_id: "user-id",
      email: "new@example.test",
      role_public_id: "role-id",
      disabled_at: nil
    }

  def list_users(reason, _filters), do: {:error, reason}
end
