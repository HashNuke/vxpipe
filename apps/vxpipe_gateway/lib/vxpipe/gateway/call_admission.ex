defmodule Vxpipe.Gateway.CallAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.Calls

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

  def start_call(_options, claim) do
    case CallEngine.start_call(claim.call.plan) do
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

  def mark_started(options, claim, incarnation_id, started_at) do
    Calls.mark_call_started(claim, incarnation_id, started_at, options)
  end

  def mark_failed(options, claim, reason) do
    Calls.mark_call_failed(claim, reason, options)
  end

  defp ttl_options(options, nil), do: options

  defp ttl_options(options, ttl_seconds) do
    Keyword.put(options, :join_token_ttl_seconds, ttl_seconds)
  end
end
