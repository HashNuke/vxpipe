defmodule Vxpipe.Calls.Diagnostics.Handoff do
  @moduledoc "Non-suspending diagnostic writes with count and retained-payload byte reservations."
  alias Vxpipe.Calls.Diagnostics.Write
  @stride 4_294_967_296
  @state 1
  @discarded 2
  @retries 3
  @overflow 4
  @enforce_keys [:writer, :token, :counters, :maximum_count, :maximum_bytes]
  @derive {Inspect, only: [:maximum_count, :maximum_bytes]}
  defstruct @enforce_keys

  def new(writer, maximum_count, maximum_bytes)
      when is_pid(writer) and is_integer(maximum_count) and maximum_count in 1..1_024 and
             is_integer(maximum_bytes) and maximum_bytes in 1..16_777_216 do
    counters = :atomics.new(4, signed: false)
    :ok = :atomics.put(counters, @state, 1)

    %__MODULE__{
      writer: writer,
      token: make_ref(),
      counters: counters,
      maximum_count: maximum_count,
      maximum_bytes: maximum_bytes
    }
  end

  def offer(%__MODULE__{} = handoff, operation) do
    with {:ok, write} <- Write.new(operation) do
      # Charge the admitted message, queued original, admission helper and DB task copies.
      bytes = :erlang.external_size(write) * 4 + 512

      with :ok <- reserve(handoff, bytes, 16) do
        deliver(handoff, write, bytes)
      end
    end
  end

  def stats(%__MODULE__{} = handoff) do
    state = :atomics.get(handoff.counters, @state)

    %{
      pending_count: div(state, 2 * @stride),
      pending_bytes: rem(div(state, 2), @stride),
      open?: rem(state, 2) == 1,
      alive?: Process.alive?(handoff.writer),
      discarded: :atomics.get(handoff.counters, @discarded),
      retries: :atomics.get(handoff.counters, @retries),
      overflow: :atomics.get(handoff.counters, @overflow)
    }
  end

  def close(%__MODULE__{} = handoff) do
    state = :atomics.get(handoff.counters, @state)

    if rem(state, 2) == 0 or
         :atomics.compare_exchange(handoff.counters, @state, state, state - 1) == :ok,
       do: :ok,
       else: close(handoff)
  end

  @doc false
  def release(handoff, bytes, outcome) when outcome in [:stored, :discarded] do
    :ok = :atomics.sub(handoff.counters, @state, 2 * (@stride + bytes))
    if outcome == :discarded, do: :atomics.add(handoff.counters, @discarded, 1)
    :ok
  end

  @doc false
  def retry(handoff), do: :atomics.add(handoff.counters, @retries, 1)

  @doc false
  def abandon(handoff) do
    close(handoff)
    state = :atomics.exchange(handoff.counters, @state, 0)
    :atomics.add(handoff.counters, @discarded, div(state, 2 * @stride))
  end

  defp reserve(handoff, bytes, attempts) do
    state = :atomics.get(handoff.counters, @state)
    count = div(state, 2 * @stride)
    pending_bytes = rem(div(state, 2), @stride)

    cond do
      rem(state, 2) == 0 or not Process.alive?(handoff.writer) ->
        {:error, :unavailable}

      attempts == 0 or count >= handoff.maximum_count or
          pending_bytes + bytes > handoff.maximum_bytes ->
        :atomics.add(handoff.counters, @overflow, 1)
        {:error, :full}

      :atomics.compare_exchange(handoff.counters, @state, state, state + 2 * (@stride + bytes)) ==
          :ok ->
        :ok

      true ->
        reserve(handoff, bytes, attempts - 1)
    end
  end

  defp deliver(handoff, write, bytes) do
    message = {:diagnostic_write, handoff.token, make_ref(), write, bytes}

    case :erlang.send(handoff.writer, message, [:nosuspend]) do
      :nosuspend ->
        release(handoff, bytes, :discarded)
        {:error, :unavailable}

      _sent ->
        :ok
    end
  end
end
