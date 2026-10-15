defmodule Vxpipe.Persistence.CallAdmissionBindingStore do
  @moduledoc "Orders durable admission ownership and cancellation on the call row."

  import Ecto.Query
  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall, TelephonyAdmissionClaim}
  alias Vxpipe.Persistence.{CallIncarnationBinding, PreparedCallRecord}
  alias Vxpipe.Persistence.Schema.{Admission, Call, JoinToken, TelephonyLeg}

  def bind(repo, subject, incarnation), do: bind(repo, subject, incarnation, :legacy)
  def bind_managed(repo, subject, incarnation), do: bind(repo, subject, incarnation, :managed)

  defp bind(repo, subject, incarnation, mode) do
    expected = subject_call(subject)

    with {:ok, id} when id == expected.id <- Ecto.UUID.cast(expected.id) do
      result = repo.transaction(fn -> bind_locked(repo, subject, expected, incarnation, mode) end)

      case result do
        {:ok, {decision, reservation, updated}} -> result(mode, decision, reservation, updated)
        {:error, _reason} = error -> error
      end
    else
      _invalid -> {:error, :not_found}
    end
  end

  defp bind_locked(repo, subject, expected, incarnation, mode) do
    query =
      from(call in Call,
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :call_spec_revision),
        join: specification in assoc(revision, :call_spec),
        where: tenant.key == ^expected.tenant_key and call.public_id == ^expected.id,
        lock: "FOR UPDATE OF c0",
        select: {call, {tenant, specification, revision}}
      )

    with {call, selection} <- repo.one(query),
         {:ok, loaded} <- PreparedCallRecord.load(call, selection),
         :ok <- matching_call(loaded, expected),
         {:ok, eligible?} <- ownership(repo, subject, call, loaded),
         {:ok, bound} <- CallIncarnationBinding.bind(repo, call, incarnation),
         {:ok, reservation, changed} <- reserve_cleanup(repo, bound, eligible?, mode),
         {:ok, updated} <- PreparedCallRecord.load(changed, selection) do
      decision =
        if eligible? and changed.state in [:admitting, :running] and
             is_nil(changed.hangup_requested_at), do: :admit, else: :cancel

      {decision, reservation, replace_call(subject, updated)}
    else
      nil -> repo.rollback(:not_found)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp result(:legacy, decision, _reservation, updated), do: {:ok, decision, updated}
  defp result(:managed, decision, reservation, updated), do: {:ok, decision, reservation, updated}

  defp reserve_cleanup(_repo, call, _eligible, :legacy), do: {:ok, nil, call}

  defp reserve_cleanup(_repo, %Call{gateway_cleanup_required: true} = call, _eligible, :managed),
    do: {:ok, :existing, call}

  defp reserve_cleanup(repo, %Call{state: :admitting, started_at: nil} = call, true, :managed) do
    case repo.update(Ecto.Changeset.change(call, gateway_cleanup_required: true)) do
      {:ok, updated} -> {:ok, :new, updated}
      {:error, _changeset} -> {:error, :cleanup_reservation_unavailable}
    end
  end

  defp reserve_cleanup(_repo, _call, _eligible, :managed),
    do: {:error, :cleanup_reservation_unavailable}

  defp matching_call(call, expected) do
    if call.id == expected.id and call.tenant_key == expected.tenant_key and
         call.room_id == expected.room_id and call.plan_digest == expected.plan_digest and
         call.call_spec_id == expected.call_spec_id and
         call.call_spec_revision == expected.call_spec_revision and call.plan == expected.plan,
       do: :ok,
       else: {:error, :call_admission_mismatch}
  end

  defp ownership(repo, %AdmissionClaim{} = claim, call, loaded) do
    query =
      from(admission in Admission,
        join: token in JoinToken,
        on: token.id == admission.join_token_id,
        where: admission.call_id == ^call.id and token.public_id == ^claim.token_id,
        select: {admission, token}
      )

    with {admission, token} <- repo.one(query),
         true <-
           admission.participant_ref == claim.participant_ref and
             admission.participant_key == claim.participant_key and
             admission.accepted_at == claim.accepted_at and token.call_id == call.id and
             token.tenant_id == call.tenant_id and token.participant_ref == claim.participant_ref and
             token.participant_key == claim.participant_key and not is_nil(token.consumed_at),
         %{participant_id: participant_id, connection: %{service: :web}} <-
           Map.get(loaded.plan.participants, claim.participant_ref),
         true <-
           participant_id == claim.participant_id and
             Map.get(loaded.participant_routes, claim.participant_key) == claim.participant_ref do
      {:ok, is_nil(admission.released_at)}
    else
      _mismatch -> {:error, :admission_not_found}
    end
  end

  defp ownership(repo, %TelephonyAdmissionClaim{} = claim, call, _loaded) do
    if TelephonyAdmissionClaim.valid_service?(claim) do
      query =
        from(leg in TelephonyLeg,
          where:
            leg.call_id == ^call.id and leg.tenant_id == ^call.tenant_id and
              leg.provider_call_leg_id == ^claim.provider_call_leg_id
        )

      case repo.one(query) do
        nil -> {:error, :telephony_leg_not_found}
        leg -> matching_leg(leg, claim)
      end
    else
      {:error, :telephony_service_mismatch}
    end
  end

  defp ownership(_repo, %PreparedCall{}, _call, %{plan: %{direction: :outgoing}}),
    do: {:ok, true}

  defp ownership(_repo, _subject, _call, _loaded), do: {:error, :call_admission_mismatch}

  defp matching_leg(leg, claim) do
    if leg.provider == Atom.to_string(claim.provider) and
         Enum.all?(
           [
             :service,
             :service_id,
             :provider_event_id,
             :provider_connection_id,
             :provider_call_control_id,
             :provider_call_session_id,
             :participant_ref,
             :participant_id,
             :accepted_at
           ],
           &(Map.fetch!(leg, &1) == Map.fetch!(claim, &1))
         ),
       do: {:ok, leg.state in ["admitting", "active"]},
       else: {:error, :telephony_leg_conflict}
  end

  defp subject_call(%PreparedCall{} = call), do: call
  defp subject_call(subject), do: subject.call
  defp replace_call(%PreparedCall{}, call), do: call
  defp replace_call(subject, call), do: %{subject | call: call}
end
