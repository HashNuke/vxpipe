defmodule Vxpipe.Calls.Test.MCPRetainedReadFixture do
  def fetch_tenant(_context, tenant),
    do:
      {:ok,
       %Vxpipe.Calls.Tenant{key: tenant, name: "Tenant", inserted_at: ~U[2026-11-07 00:00:00Z]}}

  def get_retained(context, tenant, id) do
    send(context.owner, {:metadata_read, tenant, id})
    Map.get(context, :before_return, fn -> :ok end).()
    context.result
  end
end
