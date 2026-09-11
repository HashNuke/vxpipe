defmodule Vxpipe.Gateway.Media.PlaybackFrame do
  @moduledoc false

  @enforce_keys [:sequence_number, :timestamp, :sample_rate, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sequence_number: non_neg_integer(),
          timestamp: non_neg_integer(),
          sample_rate: pos_integer(),
          payload: binary()
        }
end
