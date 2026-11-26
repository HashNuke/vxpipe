defmodule Vxpipe.CallEngine.RoomRecording.Output do
  @moduledoc false

  @enforce_keys [:writer_handle, :next_sequence]
  defstruct @enforce_keys ++ [reconnection: nil]

  @type t :: %__MODULE__{
          writer_handle: term(),
          next_sequence: non_neg_integer(),
          reconnection: nil | non_neg_integer()
        }
end
