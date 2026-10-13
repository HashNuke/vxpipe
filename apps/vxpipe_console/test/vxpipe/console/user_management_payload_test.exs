defmodule Vxpipe.Console.UserManagementPayloadTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.UserManagementPayload

  test "serializes safe user fields and server pagination" do
    user = %{
      public_id: "user-1",
      email: "member@example.test",
      password_hash: "secret-hash",
      role_public_id: "role-1",
      disabled_at: nil,
      memberships: %{"north" => :read_write}
    }

    assert UserManagementPayload.user_page(%{users: [user], total: 7}, 2, 6) == %{
             users: [
               %{
                 id: "user-1",
                 email: "member@example.test",
                 roleId: "role-1",
                 enabled: true,
                 memberships: [%{tenantId: "north", access: :read_write}]
               }
             ],
             pagination: %{page: 2, page_size: 6, total: 7, total_pages: 2}
           }
  end
end
