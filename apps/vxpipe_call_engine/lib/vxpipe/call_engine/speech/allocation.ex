defmodule Vxpipe.CallEngine.Speech.Allocation do
  @moduledoc "An exact speech allocation generation, including cancellation before provider creation."
  @enforce_keys [:scope, :generation, :owner, :consumer, :lease, :deadline, :token, :call_timeout]
  @derive {Inspect, only: [:generation, :owner, :deadline]}
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  @doc false
  def pending?(allocation), do: :atomics.get(allocation.token, 1) == 0

  @doc false
  def valid?(allocation) do
    case :atomics.get(allocation.token, 1) do
      0 -> System.monotonic_time(:millisecond) < allocation.deadline
      1 -> true
      2 -> false
    end
  end

  @doc false
  def cancel(allocation), do: :atomics.put(allocation.token, 1, 2)

  @doc false
  def activate(allocation) do
    if valid?(allocation),
      do: :atomics.compare_exchange(allocation.token, 1, 0, 1) in [:ok, 1],
      else: false
  end
end
