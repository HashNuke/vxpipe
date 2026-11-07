defmodule Vxpipe.Calls.Test.MCPOAuthPreparationFixture do
  def resolve_target({_owner, _result, entry}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, entry)

  def resolve_target({_owner, {:ok, prepared}}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, prepared.secrets["directory_entry"])

  def resolve_target({_owner, _result}, _tenant, input),
    do: Vxpipe.Calls.Test.MCPResolvedTargetFixture.resolve(input, nil)

  def prepare_target({owner, result, _entry}, tenant, input, origin, _target),
    do: prepare({owner, result}, tenant, input, origin)

  def prepare_target(context, tenant, input, origin, _target), do: prepare(context, tenant, input, origin)

  def prepare({owner, result}, _tenant, input, origin) do
    send(owner, {:oauth_prepare, input, origin})
    result
  end
end
