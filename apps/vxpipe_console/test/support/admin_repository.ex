defmodule Vxpipe.Console.Test.AdminRepository do
  @behaviour Vxpipe.Calls.AdminRepository

  @impl true
  def list_tenants({owner, result}, limit, offset) do
    send(owner, {:operator_tenants_requested, limit, offset})
    result
  end

  @impl true
  def list_call_specs({owner, result}, tenant_key, limit, offset) do
    send(owner, {:operator_call_specs_requested, tenant_key, limit, offset})
    result
  end

  @impl true
  def list_calls({owner, result}, tenant_key, call_spec_id, limit, offset) do
    send(owner, {:operator_calls_requested, tenant_key, call_spec_id, limit, offset})
    result
  end

  @impl true
  def list_services({owner, result}, tenant_key) do
    send(owner, {:operator_services_requested, tenant_key})
    result
  end

  @impl true
  def fetch_call_context({owner, result}, tenant_key, call_id) do
    send(owner, {:operator_call_context_requested, tenant_key, call_id})
    result
  end
end
