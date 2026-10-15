defmodule Vxpipe.Persistence.IdentityRoleDirectoryTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Identity.Roles
  alias Vxpipe.Persistence.IdentityRoleStore
  alias Vxpipe.Persistence.Schema.IdentityRole

  @actor %{
    user_public_id: "11111111-1111-4111-8111-111111111111",
    session_public_id: "22222222-2222-4222-8222-222222222222",
    account_kind: :admin
  }

  test "full role pages use a bounded stable order and exact counts including grant projections" do
    for suffix <- ["b", "a"] do
      Repo.insert!(
        IdentityRole.ordinary_changeset(%IdentityRole{}, %{
          public_id: Ecto.UUID.generate(),
          slug: "directory-#{suffix}",
          name: "Same name"
        })
      )
    end

    expected =
      Repo.all(
        from(r in IdentityRole, order_by: [asc: r.name, asc: r.public_id], select: r.public_id)
      )

    deps = %{roles: IdentityRoleStore}
    assert {:ok, first} = Roles.list_roles(deps, @actor, %{page_size: 1})
    assert first.total == length(expected)
    assert first.total_pages == length(expected)
    assert Enum.map(first.roles, & &1.public_id) == Enum.take(expected, 1)
    assert Enum.all?(first.roles, &is_list(&1.grants))
    assert {:ok, last} = Roles.list_roles(deps, @actor, %{page: length(expected), page_size: 1})
    assert Enum.map(last.roles, & &1.public_id) == Enum.take(expected, -1)

    assert {:error, :page_out_of_range} =
             Roles.list_roles(deps, @actor, %{page: length(expected) + 1, page_size: 1})

    assert {:error, :invalid_pagination} = IdentityRoleStore.list_page(%{page_size: 51})
  end

  test "invalid and absent role identifiers are not infrastructure failures" do
    for id <- ["not-a-role", Ecto.UUID.generate()] do
      assert {:error, :not_found} = Roles.get_role(%{roles: IdentityRoleStore}, @actor, id)

      assert {:error, :not_found} =
               Roles.affected_user_count(%{roles: IdentityRoleStore}, @actor, id)
    end
  end
end
