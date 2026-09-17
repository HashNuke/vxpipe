defmodule Vxpipe.Calls.TestAdminRepository do
  use Agent

  def start_link(result), do: Agent.start_link(fn -> result end)

  def admin_repository(agent), do: {__MODULE__, agent}

  def list_tenants(agent, limit, offset) do
    send(self(), {:admin_repository_list_tenants, limit, offset})
    Agent.get(agent, & &1)
  end
end
