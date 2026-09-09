defmodule Vxpipe.CallEngine.CallVariables.ArchivalPort do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Handoff
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}

  @derive {Inspect, except: [:handoff]}
  defstruct [:handoff]

  @type snapshot :: BaselineSnapshot.t() | UpdateSnapshot.t()
  @type t :: %__MODULE__{handoff: nil | Handoff.t()}

  @spec new(nil | Handoff.t()) :: t()
  def new(%Handoff{} = handoff), do: %__MODULE__{handoff: handoff}
  def new(nil), do: %__MODULE__{handoff: nil}

  @spec handoff(t(), snapshot()) :: :ok
  def handoff(%__MODULE__{handoff: nil}, snapshot)
      when is_struct(snapshot, BaselineSnapshot) or is_struct(snapshot, UpdateSnapshot),
      do: :ok

  def handoff(%__MODULE__{handoff: handoff}, snapshot)
      when is_struct(snapshot, BaselineSnapshot) or is_struct(snapshot, UpdateSnapshot) do
    _accepted_or_dropped = Handoff.offer(handoff, snapshot)
    :ok
  end
end
