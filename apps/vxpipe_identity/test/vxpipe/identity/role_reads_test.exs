defmodule Vxpipe.Identity.RoleReadsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Identity.{ObservedRoleReads, Roles}
  @id "11111111-1111-4111-8111-111111111111"
  @actor %{
    user_public_id: @id,
    session_public_id: "22222222-2222-4222-8222-222222222222",
    account_kind: :admin
  }
  @deps %{roles: ObservedRoleReads}

  test "role detail and counts authorize the actual actor before accessing storage" do
    for actor <- [
          nil,
          %{},
          %{account_kind: :admin},
          %{@actor | account_kind: :member},
          %{credential_kind: :platform_api_key}
        ] do
      assert {:error, :forbidden} = Roles.get_role(@deps, actor, @id)
      assert {:error, :forbidden} = Roles.affected_user_count(@deps, actor, @id)
      assert {:error, :forbidden} = Roles.list_roles(@deps, actor, %{})
      refute_received {:role_fetch, _}
      refute_received {:role_count, _}
      refute_received {:role_page, _}
    end

    assert {:ok, %{public_id: @id}} = Roles.get_role(@deps, @actor, @id)
    assert_received {:role_fetch, @id}
    assert {:ok, 3} = Roles.affected_user_count(@deps, @actor, @id)
    assert_received {:role_count, @id}
  end

  test "role pages validate bounds before repository and retain empty and out-of-range contracts" do
    for filters <- [%{page: 0}, %{page_size: 51}, %{page: "1"}, %{search: "ignored"}] do
      assert {:error, :invalid_pagination} = Roles.list_roles(@deps, @actor, filters)
      refute_received {:role_page, _}
    end

    assert {:ok, %{roles: [], page: 1, page_size: 25, total: 0, total_pages: 0}} =
             Roles.list_roles(@deps, @actor, %{})

    assert_received {:role_page, %{page: 1, page_size: 25}}

    assert {:error, :page_out_of_range} =
             Roles.list_roles(@deps, @actor, %{page: 2, page_size: 1})

    assert_received {:role_page, %{page: 2, page_size: 1}}
  end
end
