defmodule Vxpipe.Calls.Diagnostics.AdmissionGate do
  @moduledoc "Bounds unresolved task-start requests across all writers in one diagnostic pool."
  @enforce_keys [:counter, :capacity]
  @derive {Inspect, only: [:capacity]}
  defstruct @enforce_keys

  def new(capacity) when is_integer(capacity) and capacity in 1..1_024,
    do: %__MODULE__{counter: :atomics.new(1, signed: false), capacity: capacity}

  def reserve(gate), do: reserve(gate, 16)
  def pending(gate), do: :atomics.get(gate.counter, 1)
  def release(gate), do: :atomics.sub(gate.counter, 1, 1)

  defp reserve(_gate, 0), do: {:error, :admission_full}

  defp reserve(gate, attempts) do
    current = pending(gate)

    cond do
      current >= gate.capacity -> {:error, :admission_full}
      :atomics.compare_exchange(gate.counter, 1, current, current + 1) == :ok -> :ok
      true -> reserve(gate, attempts - 1)
    end
  end
end
