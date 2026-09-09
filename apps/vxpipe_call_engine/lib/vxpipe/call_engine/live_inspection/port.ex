defmodule Vxpipe.CallEngine.LiveInspection.Port do
  @moduledoc false

  @pending 1
  @rejected 2
  @open 3

  @derive {Inspect, except: [:buffer, :token, :counters]}
  @enforce_keys [:buffer, :token, :counters, :capacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          buffer: pid(),
          token: reference(),
          counters: reference(),
          capacity: pos_integer()
        }

  @spec new(pid(), pos_integer()) :: t()
  def new(buffer, capacity) when is_pid(buffer) and is_integer(capacity) and capacity > 0 do
    counters = :atomics.new(@open, signed: false)
    :ok = :atomics.put(counters, @open, 1)

    %__MODULE__{
      buffer: buffer,
      token: make_ref(),
      counters: counters,
      capacity: capacity
    }
  end

  @spec offer(t(), struct()) :: :ok | {:error, :full | :unavailable}
  def offer(%__MODULE__{} = port, record) when is_struct(record) do
    cond do
      not available?(port) -> reject(port, :unavailable)
      reserve(port) == :full -> reject(port, :full)
      true -> deliver(port, record)
    end
  end

  @spec stats(t()) :: %{pending: non_neg_integer(), rejected: non_neg_integer()}
  def stats(%__MODULE__{} = port) do
    %{pending: counter(port, @pending), rejected: counter(port, @rejected)}
  end

  @doc false
  def message(%__MODULE__{} = port, {:record, token, record}) when token == port.token,
    do: {:ok, record}

  def message(%__MODULE__{}, _message), do: :error

  @doc false
  def acknowledge(%__MODULE__{} = port) do
    _remaining = :atomics.sub_get(port.counters, @pending, 1)
    :ok
  end

  @doc false
  def discard(%__MODULE__{} = port) do
    :atomics.add(port.counters, @rejected, 1)
    acknowledge(port)
  end

  @doc false
  def close(%__MODULE__{} = port), do: :atomics.put(port.counters, @open, 0)

  defp available?(port) do
    :atomics.get(port.counters, @open) == 1 and Process.alive?(port.buffer)
  end

  defp reserve(port) do
    current = counter(port, @pending)

    cond do
      current >= port.capacity ->
        :full

      :atomics.compare_exchange(port.counters, @pending, current, current + 1) == :ok ->
        :ok

      true ->
        reserve(port)
    end
  end

  defp deliver(port, record) do
    message = {:vxpipe_live_inspection, :record, port.token, record}

    case :erlang.send(port.buffer, message, [:nosuspend]) do
      :nosuspend ->
        acknowledge(port)
        reject(port, :unavailable)

      _delivered ->
        :ok
    end
  end

  defp reject(port, reason) do
    :atomics.add(port.counters, @rejected, 1)
    {:error, reason}
  end

  defp counter(port, index), do: :atomics.get(port.counters, index)
end
