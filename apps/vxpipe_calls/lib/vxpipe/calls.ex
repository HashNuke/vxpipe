defmodule Vxpipe.Calls do
  @moduledoc "Database-neutral application workflows for durable call control-plane data."

  def mark_outgoing_call_started(call, incarnation_id, started_at, options \\ []),
    do: Vxpipe.Calls.OutgoingCalls.mark_started(call, incarnation_id, started_at, options)

  def mark_outgoing_call_failed(call, reason, options \\ []),
    do: Vxpipe.Calls.OutgoingCalls.mark_failed(call, reason, options)

  def claim_outgoing_call(
        principal,
        call_spec_id,
        initial_variables,
        idempotency_key,
        options \\ []
      ),
      do:
        Vxpipe.Calls.OutgoingCalls.claim(
          principal,
          call_spec_id,
          initial_variables,
          idempotency_key,
          options
        )

  alias Vxpipe.Calls.{
    Administration,
    Admissions,
    Archives,
    Artifacts,
    BillingEnrichments,
    CallReadAccess,
    CallDetailsInspections,
    CallDetailsFinalization,
    CallDetailsPublications,
    DemoSetup,
    CallSpecs,
    Inspections,
    OperatorAdministration,
    OperatorLoginChallenges,
    PublicationFinalizers,
    PublicationWorkers,
    TelephonyAdmissions,
    UsageProjections
  }

  def ensure_demo_tenant(authority, options \\ []),
    do: DemoSetup.ensure_tenant(authority, options)

  def issue_operator_login_challenge(verifier_secret, options \\ []),
    do: OperatorLoginChallenges.issue(verifier_secret, options)

  def consume_operator_login_challenge(token, code, verifier_secret, options \\ []),
    do: OperatorLoginChallenges.consume(token, code, verifier_secret, options)

  def list_operator_tenants(authority, options \\ []),
    do: OperatorAdministration.list_tenants(authority, options)

  def list_operator_call_specs(authority, tenant_key, options \\ []),
    do: OperatorAdministration.list_call_specs(authority, tenant_key, options)

  def list_operator_calls(authority, tenant_key, options \\ []),
    do: OperatorAdministration.list_calls(authority, tenant_key, options)

  def fetch_operator_call(authority, tenant_key, call_id, options \\ []),
    do: OperatorAdministration.fetch_call_context(authority, tenant_key, call_id, options)

  def list_operator_service_bindings(authority, scope, options \\ []),
    do: Vxpipe.Calls.OperatorServiceBindings.list(authority, scope, options)

  def delete_operator_credential(authority, owner, id, options \\ []),
    do: OperatorAdministration.delete_credential(authority, owner, id, options)

  def list_operator_services(authority, tenant_key, options \\ []),
    do: OperatorAdministration.list_services(authority, tenant_key, options)

  def create_operator_credential(
        authority,
        tenant_key,
        provider,
        name,
        auth_kind,
        payload,
        options \\ []
      ),
      do:
        OperatorAdministration.create_credential(
          authority,
          tenant_key,
          provider,
          name,
          auth_kind,
          payload,
          options
        )

  def validate_operator_credential(
        authority,
        owner,
        provider,
        name,
        auth_kind,
        payload,
        options \\ []
      ),
      do:
        OperatorAdministration.validate_credential(
          authority,
          owner,
          provider,
          name,
          auth_kind,
          payload,
          options
        )

  def update_operator_credential(
        authority,
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        options \\ []
      ),
      do:
        OperatorAdministration.update_credential(
          authority,
          tenant_key,
          credential_id,
          provider,
          auth_kind,
          payload,
          options
        )

  def bootstrap_operator_api_key(options \\ []),
    do: Vxpipe.Calls.OperatorApiKeys.bootstrap(options)

  def replace_operator_api_key(options \\ []),
    do: Vxpipe.Calls.OperatorApiKeys.replace(options)

  def revoke_operator_api_key(id, options \\ []),
    do: Vxpipe.Calls.OperatorApiKeys.revoke(id, options)

  def authenticate_operator(secret, options \\ []),
    do: Vxpipe.Calls.OperatorApiKeys.authenticate(secret, options)

  def bootstrap_tenant(name, scopes, options \\ []),
    do: Administration.bootstrap_tenant(name, scopes, options)

  def issue_api_key(tenant_key, name, scopes, options \\ []),
    do: Administration.issue_api_key(tenant_key, name, scopes, options)

  def authenticate(tenant_key, secret, required_scope, options \\ []),
    do: Administration.authenticate(tenant_key, secret, required_scope, options)

  def revoke_api_key(tenant_key, api_key_id, options \\ []),
    do: Administration.revoke_api_key(tenant_key, api_key_id, options)

  def save_call_spec(tenant_key, source, options \\ []),
    do: CallSpecs.save(tenant_key, source, options)

  def save_authorized_call_spec(authority, tenant_key, source, options \\ []),
    do: Vxpipe.Calls.CallSpecAuthoring.save(authority, tenant_key, source, options)

  def publish_authorized_call_spec(authority, tenant_key, id, revision, options \\ []),
    do: Vxpipe.Calls.CallSpecAuthoring.publish(authority, tenant_key, id, revision, options)

  def fetch_call_spec(tenant_key, call_spec_id, revision, options \\ []),
    do: CallSpecs.fetch(tenant_key, call_spec_id, revision, options)

  def publish_call_spec(tenant_key, call_spec_id, revision, options \\ []),
    do: CallSpecs.publish(tenant_key, call_spec_id, revision, options)

  def resolve_participant_route(tenant_key, route_key, options \\ []),
    do: CallSpecs.resolve_route(tenant_key, route_key, options)

  def resolve_telephony_route(scope, service, number, options \\ []),
    do: CallSpecs.resolve_telephony_route(scope, service, number, options)

  def prepare_call(principal, participant_key, initial_variables, options \\ []),
    do: Admissions.prepare(principal, participant_key, initial_variables, options)

  def fetch_call(tenant_key, call_id, options \\ []),
    do: Admissions.fetch(tenant_key, call_id, options)

  def issue_join_token(principal, call_id, participant_key, options \\ []),
    do: Admissions.issue_token(principal, call_id, participant_key, options)

  def claim_join_token(secret, expected_scope, options \\ []),
    do: Admissions.claim_token(secret, expected_scope, options)

  def release_admission(claim, options \\ []), do: Admissions.release(claim, options)

  def mark_call_started(claim, incarnation_id, started_at, options \\ []),
    do: Admissions.mark_started(claim, incarnation_id, started_at, options)

  def mark_call_failed(claim, reason, options \\ []),
    do: Admissions.mark_failed(claim, reason, options)

  def claim_incoming_telephony(scope, service, event, options \\ []),
    do: TelephonyAdmissions.claim_incoming(scope, service, event, options)

  def mark_incoming_telephony_started(claim, incarnation_id, started_at, options \\ []),
    do: TelephonyAdmissions.mark_started(claim, incarnation_id, started_at, options)

  def mark_incoming_telephony_failed(claim, reason, options \\ []),
    do: TelephonyAdmissions.mark_failed(claim, reason, options)

  def archive_variable_snapshot(snapshot, options \\ []),
    do: Archives.store_variable_snapshot(snapshot, options)

  def archive_call_fact(fact, options \\ []),
    do: Archives.store_call_fact(fact, options)

  def archive_call_artifact(artifact, options \\ []),
    do: Artifacts.store(artifact, options)

  def store_usage_observation(observation, options \\ []),
    do: UsageProjections.store(observation, options)

  def fetch_variable_snapshots(principal, call_id, options \\ []),
    do: Archives.fetch_variable_snapshots(principal, call_id, options)

  def fetch_call_facts(principal, call_id, options \\ []),
    do: Archives.fetch_call_facts(principal, call_id, options)

  def fetch_call_artifacts(principal, call_id, options \\ []),
    do: Artifacts.fetch(principal, call_id, options)

  def fetch_call_artifact(principal, call_id, artifact_id, options \\ []),
    do: Artifacts.fetch_one(principal, call_id, artifact_id, options)

  def fetch_usage_report(principal, call_id, options \\ []),
    do: UsageProjections.fetch_report(principal, call_id, options)

  def operator_call_access(authority, tenant_key),
    do: CallReadAccess.for_operator(authority, tenant_key)

  def enrich_usage_billing(principal, call_id, options \\ []),
    do: BillingEnrichments.enrich(principal, call_id, options)

  def reserve_call_details(tenant_key, call_id, snapshot, options \\ []),
    do: CallDetailsPublications.reserve(tenant_key, call_id, snapshot, options)

  def mark_call_details_published(tenant_key, call_id, publication_id, object, options \\ []),
    do:
      CallDetailsPublications.mark_published(tenant_key, call_id, publication_id, object, options)

  def publish_call_details(tenant_key, call_id, snapshot, options \\ []),
    do: PublicationWorkers.start(tenant_key, call_id, snapshot, options)

  def list_pending_call_details(limit, options \\ []),
    do: CallDetailsPublications.list_pending(limit, options)

  def resume_call_details(publication, options \\ []),
    do: PublicationWorkers.resume(publication, options)

  def assess_call_details(tenant_key, call_id, assessed_at, options \\ []),
    do: CallDetailsFinalization.assess(tenant_key, call_id, assessed_at, options)

  def finalize_call_details(tenant_key, call_id, options \\ []),
    do: PublicationFinalizers.start(tenant_key, call_id, options)

  def list_call_details(principal, call_id, options \\ []),
    do: CallDetailsInspections.list(principal, call_id, options)

  def fetch_call_details(principal, call_id, publication_id, options \\ []),
    do: CallDetailsInspections.fetch(principal, call_id, publication_id, options)

  def fetch_call_history(principal, call_id, options \\ []),
    do: Archives.fetch_call_history(principal, call_id, options)

  def list_calls(principal, options \\ []), do: Inspections.list_calls(principal, options)

  def inspect_call(principal, call_id, options \\ []),
    do: Inspections.inspect_call(principal, call_id, options)

  def inspect_live_call(principal, call_id, options \\ []),
    do: Inspections.inspect_live_call(principal, call_id, options)
end
