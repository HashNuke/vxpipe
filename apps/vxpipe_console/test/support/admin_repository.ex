defmodule Vxpipe.Console.Test.AdminRepository do
  @behaviour Vxpipe.Calls.AdminRepository

  @impl true
  def list_tenants({owner, result}, limit, offset) do
    send(owner, {:operator_tenants_requested, limit, offset})
    result
  end
end
