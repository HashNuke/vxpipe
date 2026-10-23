defmodule Vxpipe.Identity.ObservedRoleReads do
  @moduledoc false

  def list_page(filters) do
    send(self(), {:role_page, filters})
    {:ok, %{roles: [], total: 0}}
  end

  def fetch(id) do
    send(self(), {:role_fetch, id})
    {:ok, %{public_id: id}}
  end

  def count_users(id) do
    send(self(), {:role_count, id})
    {:ok, 3}
  end
end
