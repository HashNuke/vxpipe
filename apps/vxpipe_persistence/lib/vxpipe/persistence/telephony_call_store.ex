defmodule Vxpipe.Persistence.TelephonyCallStore do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Persistence.PreparedCallRecord
  alias Vxpipe.Persistence.Schema.{CallDefinition, Tenant}
  alias Vxpipe.Persistence.Schema.DefinitionRevision, as: StoredRevision
  alias Vxpipe.Persistence.Schema.TelephonyLeg, as: StoredTelephonyLeg

  @spec claim(module(), TelephonyAdmissionClaim.t(), (-> {:ok, :authorized} | {:error, term()})) ::
          {:ok, TelephonyAdmissionClaim.t()}
          | {:duplicate, TelephonyAdmissionClaim.t()}
          | {:error, term()}
  def claim(repo, %TelephonyAdmissionClaim{} = claim, authorize) when is_function(authorize, 0) do
    case existing_claim(repo, claim) do
      :none -> insert_claim(repo, claim, authorize)
      result -> result
    end
  end

  @spec mark_started(module(), TelephonyAdmissionClaim.t(), String.t(), DateTime.t()) ::
          {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}
  def mark_started(repo, %TelephonyAdmissionClaim{} = claim, incarnation_id, started_at) do
    project_lifecycle(repo, claim, fn repo, call, leg ->
      with {:ok, call} <- start_call(repo, call, incarnation_id, started_at),
           {:ok, _leg} <- activate_leg(repo, leg, incarnation_id) do
        {:ok, call}
      end
    end)
  end

  @spec mark_failed(module(), TelephonyAdmissionClaim.t(), atom(), DateTime.t()) ::
          {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}
  def mark_failed(repo, %TelephonyAdmissionClaim{} = claim, reason, failed_at) do
    project_lifecycle(repo, claim, fn repo, call, leg ->
      with {:ok, call} <- fail_call(repo, call, reason, failed_at),
           {:ok, _leg} <- end_leg(repo, leg) do
        {:ok, call}
      end
    end)
  end

  defp insert_claim(repo, claim, authorize) do
    call = claim.call

    multi =
      Multi.new()
      |> Multi.run(:selection, fn repo, _changes ->
        fetch_selection(repo, call.tenant_key, call.definition_id, call.definition_revision)
      end)
      |> Multi.run(:credentials, fn _repo, _changes -> authorize.() end)
      |> Multi.insert(:call, fn %{selection: {tenant, _definition, revision}} ->
        PreparedCallRecord.changeset(call, tenant, revision)
      end)
      |> Multi.insert(:telephony_leg, fn %{
                                           selection: {tenant, _definition, _revision},
                                           call: stored_call
                                         } ->
        leg_changeset(claim, tenant, stored_call)
      end)

    case repo.transaction(multi) do
      {:ok, %{call: stored_call, selection: selection}} ->
        with {:ok, loaded_call} <- PreparedCallRecord.load(stored_call, selection) do
          {:ok, %{claim | call: loaded_call}}
        end

      {:error, :call, changeset, _changes} ->
        if unique_error?(changeset),
          do: {:error, :call_id_conflict},
          else: {:error, :call_insert_failed}

      {:error, :telephony_leg, changeset, _changes} ->
        if unique_error?(changeset),
          do: existing_after_conflict(repo, claim),
          else: {:error, :telephony_leg_insert_failed}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp fetch_selection(repo, tenant_key, definition_id, revision_number) do
    query =
      from(revision in StoredRevision,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        join: tenant in Tenant,
        on: tenant.id == definition.tenant_id,
        where:
          tenant.key == ^tenant_key and definition.public_id == ^definition_id and
            revision.revision == ^revision_number,
        select: {tenant, definition, revision}
      )

    case repo.one(query) do
      nil -> {:error, :definition_revision_not_found}
      selection -> {:ok, selection}
    end
  end

  defp leg_changeset(claim, tenant, call) do
    StoredTelephonyLeg.changeset(%StoredTelephonyLeg{}, %{
      tenant_id: tenant.id,
      call_id: call.id,
      provider: Atom.to_string(claim.provider),
      service: claim.service,
      provider_event_id: claim.provider_event_id,
      provider_connection_id: claim.provider_connection_id,
      provider_call_control_id: claim.provider_call_control_id,
      provider_call_leg_id: claim.provider_call_leg_id,
      provider_call_session_id: claim.provider_call_session_id,
      participant_ref: claim.participant_ref,
      participant_id: claim.participant_id,
      state: "admitting",
      accepted_at: claim.accepted_at
    })
  end

  defp existing_claim(repo, claim) do
    event_claim =
      fetch_claim(
        repo,
        claim.provider,
        claim.service,
        :provider_event_id,
        claim.provider_event_id
      )

    leg_claim =
      fetch_claim(
        repo,
        claim.provider,
        claim.service,
        :provider_call_leg_id,
        claim.provider_call_leg_id
      )

    existing_outcome(event_claim, leg_claim, claim)
  end

  defp existing_after_conflict(repo, claim) do
    case existing_claim(repo, claim) do
      :none -> {:error, :telephony_leg_conflict}
      result -> result
    end
  end

  defp existing_outcome(nil, nil, _claim), do: :none

  defp existing_outcome(%TelephonyAdmissionClaim{} = existing, _leg, claim) do
    if existing.provider_call_leg_id == claim.provider_call_leg_id,
      do: {:duplicate, existing},
      else: {:error, :telephony_leg_conflict}
  end

  defp existing_outcome(nil, %TelephonyAdmissionClaim{} = existing, _claim),
    do: {:duplicate, existing}

  defp fetch_claim(repo, provider, service, field_name, value) do
    query =
      from(leg in StoredTelephonyLeg,
        join: call in assoc(leg, :call),
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where:
          leg.provider == ^Atom.to_string(provider) and leg.service == ^service and
            field(leg, ^field_name) == ^value,
        select: {leg, call, {tenant, definition, revision}}
      )

    case repo.one(query) do
      nil -> nil
      {leg, call, selection} -> to_claim(leg, call, selection)
    end
  end

  defp project_lifecycle(repo, claim, transition) do
    repo.transaction(fn ->
      with {leg, call, selection} <- fetch_stored_claim(repo, claim),
           :ok <- matching_claim(leg, call, selection, claim),
           {:ok, call} <- transition.(repo, call, leg),
           {:ok, prepared_call} <- PreparedCallRecord.load(call, selection) do
        %{claim | call: prepared_call}
      else
        nil -> repo.rollback(:telephony_leg_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:telephony_lifecycle_projection_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp fetch_stored_claim(repo, claim) do
    query =
      from(leg in StoredTelephonyLeg,
        join: call in assoc(leg, :call),
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where:
          leg.provider == ^Atom.to_string(claim.provider) and
            leg.service == ^claim.service and
            leg.provider_call_leg_id == ^claim.provider_call_leg_id,
        lock: "FOR UPDATE",
        select: {leg, call, {tenant, definition, revision}}
      )

    repo.one(query)
  end

  defp matching_claim(leg, call, {tenant, _definition, _revision}, claim) do
    if leg.provider_event_id == claim.provider_event_id and
         leg.provider_connection_id == claim.provider_connection_id and
         leg.provider_call_control_id == claim.provider_call_control_id and
         leg.provider_call_session_id == claim.provider_call_session_id and
         leg.participant_ref == claim.participant_ref and
         leg.participant_id == claim.participant_id and
         call.public_id == claim.call.id and tenant.key == claim.call.tenant_key,
       do: :ok,
       else: {:error, :telephony_leg_conflict}
  end

  defp start_call(repo, %{state: :admitting} = call, incarnation_id, started_at) do
    repo.update(Vxpipe.Persistence.Schema.Call.start_changeset(call, incarnation_id, started_at))
  end

  defp start_call(_repo, %{state: :running, incarnation_id: incarnation_id} = call, incarnation_id, _at),
    do: {:ok, call}

  defp start_call(_repo, _call, _incarnation_id, _started_at),
    do: {:error, :call_unavailable}

  defp fail_call(repo, %{state: :admitting} = call, reason, failed_at) do
    repo.update(Vxpipe.Persistence.Schema.Call.failure_changeset(call, reason, failed_at))
  end

  defp fail_call(_repo, %{state: :failed, terminal_reason: reason} = call, reason, _failed_at),
    do: {:ok, call}

  defp fail_call(_repo, _call, _reason, _failed_at), do: {:error, :call_unavailable}

  defp activate_leg(repo, %{state: "admitting"} = leg, incarnation_id) do
    repo.update(StoredTelephonyLeg.activate_changeset(leg, incarnation_id))
  end

  defp activate_leg(_repo, %{state: "active", incarnation_id: incarnation_id} = leg, incarnation_id),
    do: {:ok, leg}

  defp activate_leg(_repo, _leg, _incarnation_id), do: {:error, :telephony_leg_unavailable}

  defp end_leg(repo, %{state: "admitting"} = leg) do
    repo.update(StoredTelephonyLeg.end_changeset(leg))
  end

  defp end_leg(_repo, %{state: "ended"} = leg), do: {:ok, leg}
  defp end_leg(_repo, _leg), do: {:error, :telephony_leg_unavailable}

  defp to_claim(leg, call, selection) do
    case PreparedCallRecord.load(call, selection) do
      {:ok, prepared_call} ->
        %TelephonyAdmissionClaim{
          call: prepared_call,
          participant_ref: leg.participant_ref,
          participant_id: leg.participant_id,
          provider: stored_provider(leg.provider),
          service: leg.service,
          provider_event_id: leg.provider_event_id,
          provider_connection_id: leg.provider_connection_id,
          provider_call_control_id: leg.provider_call_control_id,
          provider_call_leg_id: leg.provider_call_leg_id,
          provider_call_session_id: leg.provider_call_session_id,
          accepted_at: leg.accepted_at
        }

      {:error, _reason} ->
        nil
    end
  end

  defp stored_provider("telnyx"), do: :telnyx
  defp stored_provider("twilio"), do: :twilio

  defp unique_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
      metadata[:constraint] == :unique
    end)
  end
end
