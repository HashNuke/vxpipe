defmodule Vxpipe.CallEngine.Diagnostics.CaptureHandoff do
  @moduledoc "Bounded non-suspending evidence offers fenced by immutable call settings and source lifetime."
  alias Vxpipe.CallEngine.Diagnostics.{CapturePacket, CallSettings}
  @stride 4_294_967_296
  @pending 1
  @open 2
  @overflow 3
  @discarded 4
  @invalid 5
  @enforce_keys [
    :receiver,
    :owner,
    :settings,
    :grant,
    :token,
    :counters,
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
             settings: nil,
             owner: receiver,
             provenance: nil,
             maximum_count: 64,
             maximum_bytes: 262_144
           ),
         owner when is_pid(owner) <- Keyword.fetch!(options, :owner),
         true <- node(owner) == node() and Process.alive?(owner),
         %CallSettings{} = settings <- Keyword.fetch!(options, :settings),
         count when is_integer(count) and count in 1..128 <-
           Keyword.fetch!(options, :maximum_count),
         bytes when is_integer(bytes) and bytes in 1_024..8_388_608 <-
           Keyword.fetch!(options, :maximum_bytes),
         {:ok, grant} <- CallSettings.grant(settings),
         true <- Process.alive?(receiver),
         {:ok, provenance} <-
           provenance(Keyword.fetch!(options, :provenance), owner, settings, grant) do
      counters = :atomics.new(5, signed: false)
      :atomics.put(counters, @open, 1)

      {:ok,
       %__MODULE__{
         receiver: receiver,
         owner: owner,
         settings: settings,
         grant: grant,
         token: make_ref(),
         counters: counters,
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
  def close(handoff), do: retire(handoff, 1)

  @doc "The first observed terminal cause; later checks cannot overwrite it."
  def closed_reason(handoff) do
    case :atomics.get(handoff.provenance, 1) do
      0 -> nil
      1 -> :source_changed
    end
  end

  @doc "Loss in any linked capture stage, independent of the first retirement cause."
  def overflowed?(handoff), do: :atomics.get(handoff.provenance, 2) == 1

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

  @doc "Also used before inference/results: source or receiver loss permanently retires this handle."
  def current?(handoff) do
    cond do
      :atomics.get(handoff.counters, @open) != 1 ->
        false

      not Process.alive?(handoff.receiver) or not Process.alive?(handoff.owner) ->
        close(handoff)
        false

      true ->
        true
    end
  end

  defp provenance(nil, _owner, _settings, _grant),
    do: {:ok, :atomics.new(2, signed: false)}

  defp provenance(
         %__MODULE__{owner: owner, settings: settings, grant: grant} = handoff,
         owner,
         settings,
         grant
       ) do
    if current?(handoff), do: {:ok, handoff.provenance}, else: {:error, :unavailable}
  end

  defp provenance(_, _, _, _), do: {:error, :unavailable}

  defp reserve(handoff, charge, attempts) do
    pending = :atomics.get(handoff.counters, @pending)

    cond do
      :atomics.get(handoff.counters, @open) != 1 ->
        {:error, :unavailable}

      attempts == 0 or div(pending, @stride) >= handoff.maximum_count or
          rem(pending, @stride) + charge > handoff.maximum_bytes ->
        # Publish shared loss before the local counter can trigger worker retirement.
        :atomics.put(handoff.provenance, 2, 1)
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
