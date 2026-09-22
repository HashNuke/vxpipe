defmodule Vxpipe.CallEngine.Speech.OutputTurn do
  @moduledoc "A consumer-authorized STS output generation, distinct from its provider turn."
  @enforce_keys [:session, :turn_ref, :ref]
  @derive {Inspect, only: [:session, :turn_ref, :ref]}
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end
