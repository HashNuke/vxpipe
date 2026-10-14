defmodule Vxpipe.Console.UserManagementPayload do
  @moduledoc "Public account and role response shapes for the Console."

  def user_page(%{users: users, total: total}, page, page_size) do
    %{
      users: Enum.map(users, &user/1),
      pagination: %{
        page: page,
        page_size: page_size,
        total: total,
        total_pages: if(total == 0, do: 0, else: div(total + page_size - 1, page_size))
      }
    }
  end

  def user(record) do
    %{
      id: record.public_id,
      email: record.email,
      roleId: record.role_public_id,
      enabled: is_nil(record.disabled_at),
      memberships:
        record
        |> Map.get(:memberships, %{})
        |> Enum.sort_by(fn {tenant, _access} -> tenant end)
        |> Enum.map(fn {tenant, access} -> %{tenantId: tenant, access: access} end)
    }
  end

  def role(record) do
    %{
      id: record.public_id,
      name: record.name,
      kind: if(record.kind in [:admin, :superadmin], do: record.kind, else: nil),
      revision: record.revision,
      grants: Enum.map(record.grants, &Map.take(&1, [:permission, :scope]))
    }
  end

  def role_option(record) do
    %{
      id: record.public_id,
      name: record.name,
      kind: if(record.kind in [:admin, :superadmin], do: record.kind, else: nil)
    }
  end
end
