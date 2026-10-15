defmodule Vxpipe.Console.Test.DemoTenantRepository do
  @behaviour Vxpipe.Calls.DemoTenantRepository

  @impl true
  def fetch({owner, result}) do
    send(owner, :demo_tenant_fetched)
    result
  end

  @impl true
  def ensure({owner, result}, candidate) do
    send(owner, {:demo_tenant_requested, candidate})
    result
  end
end
