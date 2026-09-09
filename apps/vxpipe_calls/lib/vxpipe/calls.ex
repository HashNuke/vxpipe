defmodule Vxpipe.Calls do
  @moduledoc "Database-neutral application workflows for durable call control-plane data."

  alias Vxpipe.Calls.{Administration, Admissions, Definitions}

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

  def prepare_call(principal, participant_key, initial_variables, options \\ []),
    do: Admissions.prepare(principal, participant_key, initial_variables, options)

  def fetch_call(tenant_key, call_id, options \\ []),
    do: Admissions.fetch(tenant_key, call_id, options)

  def issue_join_token(principal, call_id, participant_key, options \\ []),
    do: Admissions.issue_token(principal, call_id, participant_key, options)

  def claim_join_token(secret, expected_scope, options \\ []),
    do: Admissions.claim_token(secret, expected_scope, options)

  def mark_call_started(claim, incarnation_id, started_at, options \\ []),
    do: Admissions.mark_started(claim, incarnation_id, started_at, options)

  def mark_call_failed(claim, reason, options \\ []),
    do: Admissions.mark_failed(claim, reason, options)
end
