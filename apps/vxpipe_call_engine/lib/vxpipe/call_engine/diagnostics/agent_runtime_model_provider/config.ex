defmodule Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProvider.Config do
  @moduledoc false

  @derive {Inspect, only: [:model]}
  @enforce_keys [:fixture, :model]
  defstruct @enforce_keys

  @type t :: %__MODULE__{fixture: pid(), model: String.t()}
end
