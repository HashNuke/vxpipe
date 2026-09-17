defmodule Vxpipe.Console.Test.AdminRepository do
  @behaviour Vxpipe.Calls.AdminRepository

  @impl true
  def list_tenants({owner, result}, limit, offset) do
    send(owner, {:operator_tenants_requested, limit, offset})
    result
  end

  @impl true
  def list_definitions({owner, result}, tenant_key, limit, offset) do
    send(owner, {:operator_definitions_requested, tenant_key, limit, offset})
    result
  end

  @impl true
  def list_calls({owner, result}, tenant_key, definition_id, limit, offset) do
    send(owner, {:operator_calls_requested, tenant_key, definition_id, limit, offset})
    result
  end

  @impl true
  def list_services({owner, result}, tenant_key) do
    send(owner, {:operator_services_requested, tenant_key})
    result
  end
end
