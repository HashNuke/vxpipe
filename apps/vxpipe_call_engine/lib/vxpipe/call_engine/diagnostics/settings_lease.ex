defmodule Vxpipe.CallEngine.Diagnostics.SettingsLease do
  @moduledoc "Finite local authority from a durable settings read; never an independent enable switch."
  @lease_ms 3_000
  @enforce_keys [:clock_id]
  defstruct [
    :clock_id,
    :requested_at,
    :received_at,
    :expires_at,
    :conflicted_revision,
    revision: -1,
    enabled: false,
    reason: :unknown_settings
  ]

  def new(clock_id) when is_binary(clock_id) and byte_size(clock_id) in 1..128,
    do: %__MODULE__{clock_id: :binary.copy(clock_id)}

  def duration_ms, do: @lease_ms

  @doc "Revokes local authority without forgetting revision-conflict evidence."
  def revoke(%__MODULE__{} = lease, reason)
      when reason in [:settings_unavailable, :read_timeout, :invalidated],
      do: %{lease | expires_at: nil, reason: reason}

  def accept(%__MODULE__{} = lease, snapshot, started, now, clock_id) do
    cond do
      clock_id != lease.clock_id ->
        invalidate(lease, :clock_mismatch)

      not valid_time?(started, now, lease.received_at) ->
        invalidate(lease, :clock_uncertain)

      not valid_snapshot?(snapshot) ->
        invalidate(lease, :invalid_settings)

      snapshot.revision < lease.revision or
          (lease.requested_at != nil and started <= lease.requested_at) ->
        {:error, :stale_response, lease}

      snapshot.revision == lease.revision and
          (snapshot.enabled != lease.enabled or lease.conflicted_revision == snapshot.revision) ->
        invalidate(%{lease | conflicted_revision: snapshot.revision}, :conflicting_revision)

      true ->
        next = %{
          lease
          | revision: snapshot.revision,
            enabled: snapshot.enabled,
            requested_at: started,
            received_at: now,
            expires_at: started + @lease_ms,
            conflicted_revision: nil,
            reason: nil
        }

        if now >= next.expires_at,
          do: invalidate(next, :expired_settings),
          else: {:ok, next}
    end
  end

  def status(%__MODULE__{} = lease, now, clock_id) do
    cond do
      clock_id != lease.clock_id -> {:unavailable, :clock_mismatch}
      not is_integer(now) -> {:unavailable, :clock_uncertain}
      lease.received_at != nil and now < lease.received_at -> {:unavailable, :clock_uncertain}
      lease.reason != nil -> {:unavailable, lease.reason}
      now >= lease.expires_at -> {:unavailable, :expired_settings}
      lease.enabled -> {:enabled, lease.revision}
      true -> {:disabled, lease.revision}
    end
  end

  defp valid_time?(started, now, previous),
    do:
      is_integer(started) and is_integer(now) and now >= started and
        (previous == nil or now >= previous)

  defp valid_snapshot?(%{enabled: enabled, revision: revision} = snapshot),
    do:
      map_size(snapshot) == 2 and is_boolean(enabled) and is_integer(revision) and
        revision in 0..9_223_372_036_854_775_807

  defp valid_snapshot?(_snapshot), do: false

  defp invalidate(lease, reason), do: {:error, reason, %{lease | expires_at: nil, reason: reason}}
end
