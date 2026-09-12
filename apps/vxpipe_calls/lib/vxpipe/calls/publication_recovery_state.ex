defmodule Vxpipe.Calls.PublicationRecovery.State do
  @moduledoc false

  @enforce_keys [:options, :batch_size, :scan_interval_ms, :observer]
  defstruct @enforce_keys ++ [scan_timer: nil]

  @type t :: %__MODULE__{
          options: keyword(),
          batch_size: pos_integer(),
          scan_interval_ms: pos_integer(),
          observer: nil | pid(),
          scan_timer: nil | reference()
        }
end
