defmodule Vxpipe.CallEngine.CallVariables.ArchivalPort do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.UpdateSnapshot

  @derive {Inspect, except: [:subscriber]}
  defstruct [:subscriber]

  @type t :: %__MODULE__{subscriber: nil | pid()}

  @spec new(nil | pid()) :: t()
  def new(subscriber) when is_pid(subscriber), do: %__MODULE__{subscriber: subscriber}
  def new(nil), do: %__MODULE__{subscriber: nil}

  @spec handoff(t(), UpdateSnapshot.t()) :: :ok
  def handoff(%__MODULE__{subscriber: nil}, %UpdateSnapshot{}), do: :ok

  def handoff(%__MODULE__{subscriber: subscriber}, %UpdateSnapshot{} = snapshot) do
    send(subscriber, {:vxpipe_call_variables_snapshot, snapshot})
    :ok
  end
end
