defmodule Vxpipe.Calls.TestAdminRepository do
  use Agent

  def start_link(result), do: Agent.start_link(fn -> result end)

  def admin_repository(agent), do: {__MODULE__, agent}

  def list_tenants(agent, limit, offset) do
    send(self(), {:admin_repository_list_tenants, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_definitions(agent, tenant_key, limit, offset) do
    send(self(), {:admin_repository_list_definitions, tenant_key, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_calls(agent, tenant_key, definition_id, limit, offset) do
    send(self(), {:admin_repository_list_calls, tenant_key, definition_id, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_services(agent, tenant_key) do
    send(self(), {:admin_repository_list_services, tenant_key})
    Agent.get(agent, & &1)
  end
end
