defmodule Vxpipe.Gateway.CallAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall, TelephonyAdmissionClaim}
  alias Vxpipe.Gateway.Telephony.{CallIngressBackend, IngressIdentity}

  @behaviour CallIngressBackend

  @command_timeout_seconds 5

  def authenticate(options, tenant_key, secret) do
    Calls.authenticate(tenant_key, secret, :calls, options)
  end

  def prepare(options, principal, participant_key, initial_variables, ttl_seconds) do
    Calls.prepare_call(
      principal,
      participant_key,
      initial_variables,
      ttl_options(options, ttl_seconds)
    )
  end

  def issue_token(options, principal, call_id, participant_key, ttl_seconds) do
    Calls.issue_join_token(
      principal,
      call_id,
      participant_key,
      ttl_options(options, ttl_seconds)
    )
  end

  def claim_token(options, secret, expected_scope) do
    Calls.claim_join_token(secret, expected_scope, options)
  end

  def start_call(
        _options,
        %AdmissionClaim{call: %PreparedCall{state: :running} = call} = claim
      ) do
    participant = Map.fetch!(call.plan.participants, claim.participant_ref)

    admit_running_participant(call, participant)
  end

  def start_call(options, claim) do
    participant = Map.fetch!(claim.call.plan.participants, claim.participant_ref)

    if transfer_destination?(participant) do
      {:join_error, :participant_start_failed}
    else
      start_prepared_call(options, claim)
    end
  end

  def mark_started(options, claim, incarnation_id, started_at) do
    Calls.mark_call_started(claim, incarnation_id, started_at, options)
  end

  def mark_failed(options, claim, reason) do
    Calls.mark_call_failed(claim, reason, options)
  end

  @impl CallIngressBackend
  def claim_incoming(options, %IngressIdentity{} = identity, %Event{} = event) do
    Calls.claim_incoming_telephony(identity.scope, identity.service_id, event, options)
  end

  @impl CallIngressBackend
  def start_incoming(options, %TelephonyAdmissionClaim{} = claim) do
    CallEngine.start_call(claim.call.plan, archive: archive_options(options))
  end

  @impl CallIngressBackend
  def mark_incoming_started(options, claim, incarnation_id, started_at) do
    Calls.mark_incoming_telephony_started(claim, incarnation_id, started_at, options)
  end

  @impl CallIngressBackend
  def mark_incoming_failed(options, claim, reason) do
    Calls.mark_incoming_telephony_failed(claim, reason, options)
  end

  @impl CallIngressBackend
  def handle_live_event(_options, %TelephonyAdmissionClaim{}, %Event{}) do
    {:error, :telephony_event_not_supported}
  end

  defp admit_running_participant(
         %PreparedCall{} = call,
         participant
       ) do
    if transfer_destination?(participant) do
      {:transfer_pending, participant}
    else
      join_running_participant(call, participant)
    end
  end

  defp start_prepared_call(options, claim) do
    case CallEngine.start_call(claim.call.plan, archive: archive_options(options)) do
      {:ok, room} ->
        case CallEngine.participant_snapshot(
               claim.call.tenant_key,
               claim.call.room_id,
               claim.participant_id
             ) do
          {:ok, participant} -> {:ok, room, participant}
          {:error, _reason} -> {:started, room}
        end

      {:error, _reason} ->
        {:error, :room_start_failed}
    end
  end

  defp join_running_participant(%PreparedCall{} = call, participant) do
    with %DateTime{} <- call.started_at,
         incarnation_id when is_binary(incarnation_id) and byte_size(incarnation_id) > 0 <-
           call.incarnation_id,
         {:ok, command} <-
           JoinParticipant.new(
             tenant_id: call.tenant_key,
             actor_id: call.plan.actor_id,
             room_id: call.room_id,
             participant_id: participant.participant_id,
             role: participant.kind,
             deadline: DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)
           ),
         {:ok, participant_snapshot} <- CallEngine.join_participant(command) do
      {:joined, participant_snapshot}
    else
      _unavailable -> {:join_error, :participant_start_failed}
    end
  end

  defp transfer_destination?(%{
         kind: :human,
         connection: %{service: :web, mode: :receive, admission: :transfer}
       }),
       do: true

  defp transfer_destination?(_participant), do: false

  defp ttl_options(options, nil), do: options

  defp ttl_options(options, ttl_seconds) do
    Keyword.put(options, :join_token_ttl_seconds, ttl_seconds)
  end

  defp archive_options(options), do: Keyword.get(options, :archive, enabled: false)
end
