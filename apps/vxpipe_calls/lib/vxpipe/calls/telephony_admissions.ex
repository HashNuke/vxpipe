defmodule Vxpipe.Calls.TelephonyAdmissions do
  @moduledoc "Provider-neutral incoming telephony admission workflows."

  alias Vxpipe.CallEngine.Telephony.Event

  alias Vxpipe.Calls.{
    Definitions,
    PreparedCallFactory,
    Repositories,
    TelephonyAdmissionClaim
  }

  @spec claim_incoming(
          :application | {:tenant, String.t()},
          String.t(),
          Event.t(),
          keyword()
        ) ::
          {:ok, TelephonyAdmissionClaim.t()}
          | {:duplicate, TelephonyAdmissionClaim.t()}
          | {:error, term()}
  def claim_incoming(scope, service, %Event{kind: :incoming} = event, options)
      when is_binary(service) and is_list(options) do
    with :ok <- incoming_event(event),
         {:ok, route} <- Definitions.resolve_telephony_route(scope, service, event.to, options),
         {:ok, revision} <-
           Definitions.fetch(
             route.tenant_key,
             route.definition_id,
             route.definition_revision,
             options
           ),
         {:ok, call} <- PreparedCallFactory.build(revision, %{}, :telephony, options),
         :ok <- entry_caller(route.participant_ref, call.entry_caller),
         {:ok, participant} <- Map.fetch(call.plan.participants, route.participant_ref),
         {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      claim = %TelephonyAdmissionClaim{
        call: %{call | state: :admitting},
        participant_ref: route.participant_ref,
        participant_id: participant.participant_id,
        provider: event.provider,
        service: service,
        provider_event_id: event.provider_event_id,
        provider_connection_id: event.provider_connection_id,
        provider_call_control_id: event.provider_call_control_id,
        provider_call_leg_id: event.provider_call_leg_id,
        provider_call_session_id: event.provider_call_session_id,
        accepted_at: now(options)
      }

      Repositories.call(repository, :claim_incoming_telephony, [claim])
    else
      :error -> {:error, :participant_not_found}
      {:error, _reason} = error -> error
    end
  end

  def claim_incoming(_scope, _service, %Event{}, _options),
    do: {:error, :invalid_incoming_telephony_event}

  @spec mark_started(TelephonyAdmissionClaim.t(), String.t(), DateTime.t(), keyword()) ::
          {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}
  def mark_started(
        %TelephonyAdmissionClaim{} = claim,
        incarnation_id,
        %DateTime{} = started_at,
        options
      )
      when is_binary(incarnation_id) and byte_size(incarnation_id) > 0 and is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :mark_incoming_telephony_started, [
        claim,
        incarnation_id,
        started_at
      ])
    end
  end

  def mark_started(_claim, _incarnation_id, _started_at, _options),
    do: {:error, :invalid_telephony_call_start}

  @spec mark_failed(TelephonyAdmissionClaim.t(), atom(), keyword()) ::
          {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}
  def mark_failed(%TelephonyAdmissionClaim{} = claim, reason, options)
      when reason in [:room_start_failed, :session_start_failed, :startup_unknown] and
             is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :mark_incoming_telephony_failed, [
        claim,
        reason,
        now(options)
      ])
    end
  end

  def mark_failed(_claim, _reason, _options), do: {:error, :invalid_telephony_call_failure}

  defp incoming_event(event) do
    required = [
      event.provider_event_id,
      event.provider_connection_id,
      event.provider_call_control_id,
      event.provider_call_leg_id,
      event.provider_call_session_id,
      event.from,
      event.to
    ]

    if event.provider in [:telnyx, :twilio] and match?(%DateTime{}, event.occurred_at) and
         Enum.all?(required, &(is_binary(&1) and byte_size(&1) > 0)) do
      :ok
    else
      {:error, :invalid_incoming_telephony_event}
    end
  end

  defp entry_caller(participant_ref, participant_ref), do: :ok
  defp entry_caller(_participant_ref, _entry_caller), do: {:error, :participant_not_entry_caller}

  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
end
