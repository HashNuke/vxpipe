defmodule Vxpipe.Persistence.TelephonyCallStore do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Persistence.PreparedCallRecord
  alias Vxpipe.Persistence.Schema.{CallDefinition, Tenant}
  alias Vxpipe.Persistence.Schema.DefinitionRevision, as: StoredRevision
  alias Vxpipe.Persistence.Schema.TelephonyLeg, as: StoredTelephonyLeg

  @spec claim(module(), TelephonyAdmissionClaim.t()) ::
          {:ok, TelephonyAdmissionClaim.t()}
          | {:duplicate, TelephonyAdmissionClaim.t()}
          | {:error, term()}
  def claim(repo, %TelephonyAdmissionClaim{} = claim) do
    case existing_claim(repo, claim) do
      :none -> insert_claim(repo, claim)
      result -> result
    end
  end

  defp insert_claim(repo, claim) do
    call = claim.call

    multi =
      Multi.new()
      |> Multi.run(:selection, fn repo, _changes ->
        fetch_selection(repo, call.tenant_key, call.definition_id, call.definition_revision)
      end)
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
