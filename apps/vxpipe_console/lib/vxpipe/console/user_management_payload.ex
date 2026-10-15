defmodule Vxpipe.Console.UserManagementPayload do
  @moduledoc "Public account and role response shapes for the Console."

  alias Vxpipe.Gateway.AccountJSON

  def user_page(%{users: users, total: total}, page, page_size) do
    AccountJSON.user_page(
      %{
        users: users,
        page: page,
        page_size: page_size,
        total: total,
        total_pages: if(total == 0, do: 0, else: div(total + page_size - 1, page_size))
      },
      :http
    )
  end

  def user(record), do: AccountJSON.user(record, :http)

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
