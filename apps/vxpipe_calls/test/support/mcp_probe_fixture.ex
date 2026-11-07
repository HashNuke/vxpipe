defmodule Vxpipe.Calls.Test.MCPProbeFixture do
  def resolve_target({owner, result, {:on_check, _}}, tenant, input),
    do: resolve_target({owner, result}, tenant, input)

  def resolve_target({_owner, _result, entry}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, entry)

  def resolve_target({_owner, {:ok, checked}}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, checked.connection[:directory_entry])

  def resolve_target({_owner, _result}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, nil)

  def check_target({owner, result, {:on_check, action}}, tenant, input, _target) do
    send(owner, {:mcp_probe, tenant, input})
    action.()
    result
  end

  def check_target({owner, result, _entry}, tenant, input, _target),
    do: check({owner, result}, tenant, input)

  def check_target(context, tenant, input, _target), do: check(context, tenant, input)

  def discover({owner, result}, tenant, input) do
    send(owner, {:mcp_preflight, tenant, input})
    result
  end

  def check({owner, result}, tenant, input) do
    send(owner, {:mcp_probe, tenant, input})
    result
  end

  def check_saved({owner, result}, tenant, input, entry) do
    send(owner, {:mcp_probe_saved, tenant, input, entry})
    result
  end
end
