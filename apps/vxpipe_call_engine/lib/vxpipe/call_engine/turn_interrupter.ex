defmodule Vxpipe.CallEngine.TurnInterrupter do
  @moduledoc false

  @enforce_keys [:participant_id, :connection_id, :command_id, :correlation_id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t()
        }
end
