defmodule Vxpipe.Console.Test.AccessKeyRepository do
  @moduledoc false

  def list(pid, scope, platform?, query) do
    send(pid, {:key_list, scope, platform?, query})
    {:ok, %{keys: [metadata()], page: query.page, page_size: query.limit, total: 1}}
  end

  def tenants(pid, scope, query) do
    send(pid, {:key_tenants, scope, query})
    {:ok, %{tenants: [metadata().tenant], page: query.page, page_size: query.limit, total: 1}}
  end

  def insert(pid, record) do
    send(pid, {:key_insert, record})
    {:ok, Map.merge(metadata(), Map.take(record, [:id, :name, :kind, :last_four]))}
  end

  def fetch(_pid, id), do: {:ok, %{metadata() | id: id}}
  def revoke(_pid, _id, _now), do: :ok

  defp metadata do
    %{
      id: "01900000-0000-7000-8000-000000000001",
      name: "Backend",
      kind: "calls",
      last_four: "abcd",
      created_at: ~U[2026-10-15 00:00:00Z],
      tenant: %{key: "AAAAAAAAAAAAAAAA", name: "Acme"}
    }
  end
end
