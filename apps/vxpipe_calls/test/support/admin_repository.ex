defmodule Vxpipe.Calls.TestAdminRepository do
  use Agent

  def start_link(result), do: Agent.start_link(fn -> result end)

  def admin_repository(agent), do: {__MODULE__, agent}

  def search_tenants(agent, scope, query, limit, offset) do
    send(self(), {:tenant_search, scope, query, limit, offset})
    Agent.get(agent, & &1)
  end

  def tenant_candidates(agent, scope, limit) do
    send(self(), {:tenant_candidates, scope, limit})
    Agent.get(agent, & &1)
  end

  def list_tenants(agent, limit, offset) do
    send(self(), {:admin_repository_list_tenants, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_tenants_scoped(agent, scope, limit, offset) do
    send(self(), {:admin_repository_list_tenants_scoped, scope, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_call_specs(agent, tenant_key, limit, offset) do
    send(self(), {:admin_repository_list_call_specs, tenant_key, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_calls(agent, tenant_key, call_spec_id, limit, offset) do
    send(self(), {:admin_repository_list_calls, tenant_key, call_spec_id, limit, offset})
    Agent.get(agent, & &1)
  end

  def list_services(agent, tenant_key) do
    send(self(), {:admin_repository_list_services, tenant_key})
    Agent.get(agent, & &1)
  end

  def fetch_call_context(agent, tenant_key, call_id) do
    send(self(), {:admin_repository_fetch_call_context, tenant_key, call_id})
    Agent.get(agent, & &1)
  end
end
