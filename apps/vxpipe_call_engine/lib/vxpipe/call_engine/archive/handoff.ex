defmodule Vxpipe.CallEngine.Archive.Handoff do
  @moduledoc "A strictly bounded, non-suspending handoff to one room archive subscriber."

  @pending 1
  @accepted 2
  @overflow 3
  @unavailable 4
  @discarded 5
  @retries 6
  @open 7

  @derive {Inspect, except: [:subscriber, :token, :counters]}
  @enforce_keys [:subscriber, :token, :counters, :capacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          subscriber: pid(),
          token: reference(),
          counters: reference(),
          capacity: pos_integer()
        }

  @doc false
  @spec new(pid(), pos_integer()) :: t()
  def new(subscriber, capacity)
      when is_pid(subscriber) and is_integer(capacity) and capacity > 0 do
    counters = :atomics.new(@open, signed: false)
    :ok = :atomics.put(counters, @open, 1)

    %__MODULE__{
      subscriber: subscriber,
      token: make_ref(),
      counters: counters,
      capacity: capacity
    }
  end

  @spec offer(t(), term()) :: :ok | {:error, :full | :unavailable}
  def offer(%__MODULE__{} = handoff, fact) do
    cond do
      not available?(handoff) ->
        unavailable(handoff)

      reserve(handoff) == :full ->
        :atomics.add(handoff.counters, @overflow, 1)
        {:error, :full}

      true ->
        deliver(handoff, fact)
    end
  end

  @spec source_started(t(), pid()) :: :ok
  def source_started(%__MODULE__{} = handoff, source) when is_pid(source) do
    notify(handoff, {:source_started, source})
  end

  @spec source_stopped(t(), term()) :: :ok
  def source_stopped(%__MODULE__{} = handoff, reason) do
    close(handoff)
    notify(handoff, {:source_stopped, reason})
  end

  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = handoff) do
    open? = open?(handoff)
    alive? = Process.alive?(handoff.subscriber)
    pending = counter(handoff, @pending)
    overflow = counter(handoff, @overflow)
    unavailable = counter(handoff, @unavailable)
    discarded = counter(handoff, @discarded)

    %{
      accepted: counter(handoff, @accepted),
      alive?: alive?,
      capacity: handoff.capacity,
      discarded: discarded,
      incomplete?:
        overflow > 0 or unavailable > 0 or discarded > 0 or (not alive? and open?) or
          (not alive? and pending > 0),
      open?: open?,
      overflow: overflow,
      pending: pending,
      retries: counter(handoff, @retries),
      unavailable: unavailable
    }
  end

  @doc false
  def message(%__MODULE__{} = handoff, {:fact, token, fact}) when token == handoff.token,
    do: {:ok, {:fact, fact}}

  def message(%__MODULE__{} = handoff, {:source_started, token, source})
      when token == handoff.token and is_pid(source),
      do: {:ok, {:source_started, source}}

  def message(%__MODULE__{} = handoff, {:source_stopped, token, reason})
      when token == handoff.token,
      do: {:ok, {:source_stopped, reason}}

  def message(%__MODULE__{}, _message), do: :error

  @doc false
  def acknowledge(%__MODULE__{} = handoff) do
    _remaining = :atomics.sub_get(handoff.counters, @pending, 1)
    :ok
  end

  @doc false
  def retry(%__MODULE__{} = handoff) do
    :atomics.add(handoff.counters, @retries, 1)
    :ok
  end

  @doc false
  def discard(%__MODULE__{} = handoff) do
    :atomics.add(handoff.counters, @discarded, 1)
    acknowledge(handoff)
  end

  @doc false
  def abandon_pending(%__MODULE__{} = handoff) do
    abandoned = :atomics.exchange(handoff.counters, @pending, 0)
    :atomics.add(handoff.counters, @discarded, abandoned)
    abandoned
  end

  @doc false
  def close(%__MODULE__{} = handoff) do
    :ok = :atomics.put(handoff.counters, @open, 0)
  end

  defp available?(handoff), do: open?(handoff) and Process.alive?(handoff.subscriber)
  defp open?(handoff), do: counter(handoff, @open) == 1
  defp counter(handoff, index), do: :atomics.get(handoff.counters, index)

  defp reserve(handoff) do
    current = counter(handoff, @pending)

    cond do
      current >= handoff.capacity ->
        :full

      :atomics.compare_exchange(handoff.counters, @pending, current, current + 1) == :ok ->
        :ok

      true ->
        reserve(handoff)
    end
  end

  defp deliver(handoff, fact) do
    message = {:vxpipe_archive, :fact, handoff.token, fact}

    case :erlang.send(handoff.subscriber, message, [:nosuspend]) do
      :nosuspend ->
        acknowledge(handoff)
        unavailable(handoff)

      _delivered ->
        :atomics.add(handoff.counters, @accepted, 1)
        :ok
    end
  end

  defp notify(handoff, {:source_started, source}) do
    message = {:vxpipe_archive, :source_started, handoff.token, source}
    _result = :erlang.send(handoff.subscriber, message, [:nosuspend])
    :ok
  end

  defp notify(handoff, {:source_stopped, reason}) do
    message = {:vxpipe_archive, :source_stopped, handoff.token, reason}
    _result = :erlang.send(handoff.subscriber, message, [:nosuspend])
    :ok
  end

  defp unavailable(handoff) do
    :atomics.add(handoff.counters, @unavailable, 1)
    {:error, :unavailable}
  end
end
