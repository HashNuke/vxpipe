defmodule Vxpipe.Calls.Test.MCPConnectionTargetFixture do
  def fetch_tenant(context, tenant),
    do: Vxpipe.Calls.Test.MCPRepositoryFixture.fetch_tenant(context, tenant)

  def resolve_target(context, tenant, input) do
    send(context.owner, {:target_resolved, tenant, input})
    if context[:resolve_action], do: context.resolve_action.()
    {:ok, context.target}
  end

  def find_identity(context, tenant, identity) do
    send(context.owner, {:identity_checked, tenant, identity})
    if context[:lookup_action], do: context.lookup_action.()
    {:ok, context.existing}
  end

  def check(context, tenant, input) do
    send(context.owner, {:credentials_checked, tenant, input})
    {:error, :mcp_authentication_required}
  end

  def check_target(context, tenant, input, target) do
    send(context.owner, {:target_checked, target})
    check(context, tenant, input)
  end

  def prepare(context, tenant, input, _origin) do
    send(context.owner, {:oauth_prepared, tenant, input})
    {:error, :oauth_registration_unavailable}
  end

  def prepare_target(context, tenant, input, origin, target) do
    send(context.owner, {:target_prepared, target})
    prepare(context, tenant, input, origin)
  end
end
