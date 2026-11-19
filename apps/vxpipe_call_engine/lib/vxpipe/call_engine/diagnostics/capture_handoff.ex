defmodule Vxpipe.CallEngine.Diagnostics.CaptureHandoff do
  @moduledoc "Bounded non-suspending evidence offers fenced by continuous app-settings authority."
  alias Vxpipe.CallEngine.Diagnostics.{CapturePacket, SettingsProjection}
  @stride 4_294_967_296
  @pending 1
  @open 2
  @overflow 3
  @discarded 4
  @invalid 5
  @enforce_keys [
    :receiver,
    :owner,
    :projection,
    :grant,
    :token,
    :counters,
    :deadline,
    :provenance,
    :maximum_count,
    :maximum_bytes
  ]
  @derive {Inspect, only: [:maximum_count, :maximum_bytes]}
  defstruct @enforce_keys

  def new(receiver, options \\ []) do
    with true <- is_pid(receiver) and node(receiver) == node(),
         {:ok, options} <-
           Keyword.validate(options,
             projection: SettingsProjection,
             owner: receiver,
             provenance: nil,
             maximum_count: 64,
             maximum_bytes: 262_144
           ),
         owner when is_pid(owner) <- Keyword.fetch!(options, :owner),
         true <- node(owner) == node() and Process.alive?(owner),
         projection when is_atom(projection) <- Keyword.fetch!(options, :projection),
         count when is_integer(count) and count in 1..128 <-
           Keyword.fetch!(options, :maximum_count),
         bytes when is_integer(bytes) and bytes in 1_024..8_388_608 <-
           Keyword.fetch!(options, :maximum_bytes),
         {:ok, grant, _now, expires_at} <- SettingsProjection.grant_snapshot(projection),
         true <- Process.alive?(receiver),
         {:ok, provenance} <-
           provenance(Keyword.fetch!(options, :provenance), owner, projection, grant) do
      deadline = :atomics.new(1, signed: true)
      :atomics.put(deadline, 1, expires_at)
      counters = :atomics.new(5, signed: false)
      :atomics.put(counters, @open, 1)

      {:ok,
       %__MODULE__{
         receiver: receiver,
         owner: owner,
         projection: projection,
         grant: grant,
         token: make_ref(),
         counters: counters,
         deadline: deadline,
         provenance: provenance,
         maximum_count: count,
         maximum_bytes: bytes
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def offer(%__MODULE__{} = handoff, packet) do
    with true <- current?(handoff),
         {:ok, charge} <- CapturePacket.charge(packet),
         :ok <- reserve(handoff, charge, 16) do
      deliver(handoff, packet, charge)
    else
      false ->
        {:error, :unavailable}

      {:error, :invalid_evidence} = error ->
        :atomics.add(handoff.counters, @invalid, 1)
        error

      error ->
        error
    end
  end

  @doc "Rechecks authority on receipt; the consumer retains the charge until work settles."
  def message(handoff, {:vxpipe_diagnostic_capture, token, grant, packet, charge})
      when token == handoff.token and grant == handoff.grant do
    if current?(handoff) do
      {:ok, packet, charge}
    else
      release(handoff, charge, :discarded)
      {:error, :revoked}
    end
  end

  def message(_handoff, _message), do: :error

  @doc "Irreversibly closes this epoch; the consumer must discard its queued audio."
  def close(handoff) do
    deadline = :atomics.get(handoff.deadline, 1)
    reason = if renew_before_expiry?(handoff, deadline), do: 1, else: 2
    retire(handoff, reason)
  end

  @doc "The first observed terminal cause; later checks cannot overwrite it."
  def closed_reason(handoff) do
    case :atomics.get(handoff.provenance, 1) do
      0 -> nil
      1 -> :source_changed
      2 -> :lease_expired
    end
  end

  defp retire(handoff, reason) do
    _ = :atomics.compare_exchange(handoff.provenance, 1, 0, reason)
    :atomics.put(handoff.counters, @open, 0)
  end

  @doc false
  def release(handoff, charge, outcome) when outcome in [:processed, :discarded] do
    :atomics.sub(handoff.counters, @pending, @stride + charge)
    if outcome == :discarded, do: :atomics.add(handoff.counters, @discarded, 1)
    :ok
  end

  def stats(handoff) do
    pending = :atomics.get(handoff.counters, @pending)

    %{
      pending_count: div(pending, @stride),
      pending_bytes: rem(pending, @stride),
      open?: :atomics.get(handoff.counters, @open) == 1,
      overflow: :atomics.get(handoff.counters, @overflow),
      discarded: :atomics.get(handoff.counters, @discarded),
      invalid: :atomics.get(handoff.counters, @invalid)
    }
  end

  @doc "Also used before inference/results: a lost grant permanently retires this handle."
  def current?(handoff) do
    previous_deadline = :atomics.get(handoff.deadline, 1)

    cond do
      :atomics.get(handoff.counters, @open) != 1 ->
        false

      not Process.alive?(handoff.receiver) or not Process.alive?(handoff.owner) ->
        close(handoff)
        false

      renew_before_expiry?(handoff, previous_deadline) ->
        true

      true ->
        retire(handoff, 2)
        false
    end
  end

  defp provenance(nil, _owner, _projection, _grant),
    do: {:ok, :atomics.new(1, signed: false)}

  defp provenance(
         %__MODULE__{owner: owner, projection: projection, grant: grant} = handoff,
         owner,
         projection,
         grant
       ) do
    if current?(handoff), do: {:ok, handoff.provenance}, else: {:error, :unavailable}
  end

  defp provenance(_, _, _, _), do: {:error, :unavailable}

  defp renew_before_expiry?(handoff, previous_deadline) do
    case SettingsProjection.grant_snapshot(handoff.projection) do
      {:ok, grant, now, expires_at} when grant == handoff.grant and now < previous_deadline ->
        # A concurrent check may already have renewed the deadline. Never regress
        # it, and never let a newly published lease revive an expired consumer.
        if expires_at > previous_deadline do
          :atomics.compare_exchange(handoff.deadline, 1, previous_deadline, expires_at)
        end

        :atomics.get(handoff.counters, @open) == 1

      _ ->
        false
    end
  end

  defp reserve(handoff, charge, attempts) do
    pending = :atomics.get(handoff.counters, @pending)

    cond do
      :atomics.get(handoff.counters, @open) != 1 ->
        {:error, :unavailable}

      attempts == 0 or div(pending, @stride) >= handoff.maximum_count or
          rem(pending, @stride) + charge > handoff.maximum_bytes ->
        :atomics.add(handoff.counters, @overflow, 1)
        {:error, :full}

      :atomics.compare_exchange(handoff.counters, @pending, pending, pending + @stride + charge) ==
          :ok ->
        :ok

      true ->
        reserve(handoff, charge, attempts - 1)
    end
  end

  defp deliver(handoff, packet, charge) do
    if current?(handoff) do
      copy = CapturePacket.copy(packet)
      message = {:vxpipe_diagnostic_capture, handoff.token, handoff.grant, copy, charge}

      case :erlang.send(handoff.receiver, message, [:nosuspend]) do
        :nosuspend ->
          release(handoff, charge, :discarded)
          {:error, :unavailable}

        _sent ->
          :ok
      end
    else
      release(handoff, charge, :discarded)
      {:error, :unavailable}
    end
  end
end
