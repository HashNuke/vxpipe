defmodule Vxpipe.Calls.TestMemoryAdmissionBinding do
  @moduledoc false
  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall, TelephonyAdmissionClaim}

  def bind(agent, subject, incarnation), do: bind(agent, subject, incarnation, :legacy)
  def bind_managed(agent, subject, incarnation), do: bind(agent, subject, incarnation, :managed)

  defp bind(agent, subject, incarnation, mode) do
    expected = call(subject)

    Agent.get_and_update(agent, fn state ->
      with {:ok, current} <- Map.fetch(state.calls, {expected.tenant_key, expected.id}),
           true <-
             current.room_id == expected.room_id and current.plan_digest == expected.plan_digest,
           {:ok, eligible?} <- ownership(state, subject),
           :ok <- same_incarnation(current, incarnation),
           {:ok, reservation, updated} <- reserve(current, eligible?, mode) do
        updated = %{updated | incarnation_id: incarnation, incarnation_binding_verified: true}

        decision =
          if eligible? and current.state in [:admitting, :running] and
               is_nil(current.hangup_requested_at), do: :admit, else: :cancel

        {result(mode, decision, reservation, replace_call(subject, updated)),
         %{state | calls: Map.put(state.calls, {current.tenant_key, current.id}, updated)}}
      else
        :error -> {{:error, :not_found}, state}
        false -> {{:error, :call_admission_mismatch}, state}
        {:error, _reason} = error -> {error, state}
      end
    end)
  end

  defp result(:legacy, decision, _reservation, subject), do: {:ok, decision, subject}
  defp result(:managed, decision, reservation, subject), do: {:ok, decision, reservation, subject}
  defp reserve(call, _eligible, :legacy), do: {:ok, nil, call}

  defp reserve(%{gateway_cleanup_required: true} = call, _eligible, :managed),
    do: {:ok, :existing, call}

  defp reserve(%{state: :admitting, started_at: nil} = call, true, :managed),
    do: {:ok, :new, %{call | gateway_cleanup_required: true}}

  defp reserve(_call, _eligible, :managed), do: {:error, :cleanup_reservation_unavailable}

  defp ownership(state, %AdmissionClaim{} = subject) do
    case Map.fetch(state.admissions, {subject.call.id, subject.participant_ref, subject.token_id}) do
      {:ok, admission} -> {:ok, is_nil(admission.released_at)}
      :error -> {:error, :admission_not_found}
    end
  end

  defp ownership(state, %TelephonyAdmissionClaim{} = subject) do
    key =
      {subject.call.tenant_key, subject.service_id, subject.provider,
       subject.provider_call_leg_id}

    case Map.fetch(state.telephony_leg_claims, key) do
      {:ok, stored} ->
        if TelephonyAdmissionClaim.same_leg?(stored, subject),
          do: {:ok, true},
          else: {:error, :telephony_leg_conflict}

      :error ->
        {:error, :telephony_leg_not_found}
    end
  end

  defp ownership(_state, %PreparedCall{plan: %{direction: :outgoing}}), do: {:ok, true}

  defp same_incarnation(%{incarnation_id: nil}, _incarnation), do: :ok
  defp same_incarnation(%{incarnation_id: incarnation}, incarnation), do: :ok
  defp same_incarnation(_call, _incarnation), do: {:error, :call_incarnation_mismatch}
  defp call(%PreparedCall{} = subject), do: subject
  defp call(subject), do: subject.call
  defp replace_call(%PreparedCall{}, call), do: call
  defp replace_call(subject, call), do: %{subject | call: call}
end
