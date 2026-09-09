defmodule Vxpipe.Calls do
  @moduledoc "Database-neutral application workflows for durable call control-plane data."

  alias Vxpipe.Calls.{Administration, Definitions}

  def bootstrap_tenant(name, scopes, options \\ []),
    do: Administration.bootstrap_tenant(name, scopes, options)

  def issue_api_key(tenant_key, name, scopes, options \\ []),
    do: Administration.issue_api_key(tenant_key, name, scopes, options)

  def authenticate(tenant_key, secret, required_scope, options \\ []),
    do: Administration.authenticate(tenant_key, secret, required_scope, options)

  def revoke_api_key(tenant_key, api_key_id, options \\ []),
    do: Administration.revoke_api_key(tenant_key, api_key_id, options)

  def save_definition(tenant_key, source, options \\ []),
    do: Definitions.save(tenant_key, source, options)

  def fetch_definition(tenant_key, definition_id, revision, options \\ []),
    do: Definitions.fetch(tenant_key, definition_id, revision, options)

  def publish_definition(tenant_key, definition_id, revision, options \\ []),
    do: Definitions.publish(tenant_key, definition_id, revision, options)

  def resolve_participant_route(tenant_key, route_key, options \\ []),
    do: Definitions.resolve_route(tenant_key, route_key, options)
end
