defmodule Vxpipe.Artifacts.Handoff do
  @moduledoc "A non-suspending bounded handoff from live recording to an artifact writer."

  alias Vxpipe.Artifacts.Chunk

  @pending 1
  @rejected 2
  @closed 3

  @derive {Inspect, except: [:token, :counters]}
  @enforce_keys [:writer, :token, :counters, :capacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          writer: pid(),
          token: reference(),
          counters: reference(),
          capacity: pos_integer()
        }

  @spec new(pid(), pos_integer()) :: t()
  def new(writer, capacity) when is_pid(writer) and is_integer(capacity) and capacity > 0 do
    counters = :atomics.new(3, signed: false)
    %__MODULE__{writer: writer, token: make_ref(), counters: counters, capacity: capacity}
  end

  @spec offer(t(), Chunk.t()) :: :ok | {:error, :closed | :full | :invalid_chunk}
  def offer(%__MODULE__{} = handoff, %Chunk{} = chunk) do
    cond do
      not Chunk.valid?(chunk) -> {:error, :invalid_chunk}
      closed?(handoff) -> {:error, :closed}
      true -> reserve_and_send(handoff, chunk)
    end
  end

  def offer(%__MODULE__{}, _chunk), do: {:error, :invalid_chunk}

  @doc false
  @spec message(t(), term()) :: {:ok, Chunk.t()} | :error
  def message(%__MODULE__{token: token}, {:vxpipe_artifact_chunk, token, %Chunk{} = chunk}),
    do: {:ok, chunk}

  def message(%__MODULE__{}, _message), do: :error

  @doc false
  @spec acknowledge(t()) :: :ok
  def acknowledge(%__MODULE__{} = handoff) do
    _remaining = :atomics.sub_get(handoff.counters, @pending, 1)
    :ok
  end

  @doc false
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = handoff) do
    :ok = :atomics.put(handoff.counters, @closed, 1)
  end

  @doc false
  @spec abandon_pending(t()) :: non_neg_integer()
  def abandon_pending(%__MODULE__{} = handoff) do
    :atomics.exchange(handoff.counters, @pending, 0)
  end

  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = handoff) do
    %{
      pending: :atomics.get(handoff.counters, @pending),
      rejected: :atomics.get(handoff.counters, @rejected),
      closed?: closed?(handoff)
    }
  end

  defp reserve_and_send(handoff, chunk) do
    pending = :atomics.add_get(handoff.counters, @pending, 1)

    cond do
      pending > handoff.capacity -> reject_full(handoff)
      closed?(handoff) -> reject_closed(handoff)
      true -> send_chunk(handoff, chunk)
    end
  end

  defp reject_full(handoff) do
    _pending = :atomics.sub_get(handoff.counters, @pending, 1)
    _rejected = :atomics.add_get(handoff.counters, @rejected, 1)
    {:error, :full}
  end

  defp reject_closed(handoff) do
    _pending = :atomics.sub_get(handoff.counters, @pending, 1)
    {:error, :closed}
  end

  defp send_chunk(handoff, chunk) do
    message = {:vxpipe_artifact_chunk, handoff.token, chunk}

    case :erlang.send(handoff.writer, message, [:nosuspend]) do
      :nosuspend ->
        _pending = :atomics.sub_get(handoff.counters, @pending, 1)
        _rejected = :atomics.add_get(handoff.counters, @rejected, 1)
        {:error, :full}

      _message ->
        :ok
    end
  end

  defp closed?(handoff), do: :atomics.get(handoff.counters, @closed) == 1
end
