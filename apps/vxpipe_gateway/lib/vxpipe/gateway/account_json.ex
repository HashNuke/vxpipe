defmodule Vxpipe.Gateway.AccountJSON do
  @moduledoc "Safe account projections with compatible HTTP and canonical MCP field names."

  def user(record, mode) when mode in [:http, :mcp] do
    {id_key, role_key, tenant_key} =
      if mode == :http, do: {:id, :roleId, :tenantId}, else: {:user_id, :role_id, :tenant_key}

    %{
      id_key => record.public_id,
      :email => record.email,
      role_key => record.role_public_id,
      :enabled => is_nil(record.disabled_at),
      :memberships =>
        record
        |> Map.get(:memberships, %{})
        |> Enum.sort_by(fn {tenant, _access} -> tenant end)
        |> Enum.map(fn {tenant, access} -> %{tenant_key => tenant, :access => access} end)
    }
  end

  def user_page(%{users: users} = page, mode) do
    key = if mode == :http, do: :users, else: :items
    %{key => Enum.map(users, &user(&1, mode)), :pagination => pagination(page)}
  end

  def role_page(%{roles: roles} = page, mode) do
    key = if mode == :http, do: :roles, else: :items
    %{key => Enum.map(roles, &role(&1, mode)), :pagination => pagination(page)}
  end

  defp role(record, mode) do
    key = if mode == :http, do: :id, else: :role_id

    %{
      key => record.public_id,
      :name => record.name,
      :kind => if(record.kind in [:admin, :superadmin], do: record.kind, else: nil)
    }
  end

  defp pagination(page), do: Map.take(page, [:page, :page_size, :total, :total_pages])
end
