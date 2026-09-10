defmodule Vxpipe.CallEngine.OpeningAudio.Asset do
  @moduledoc false

  @derive {Inspect, only: [:codec, :sample_rate, :channels, :byte_order, :duration_ms]}
  @enforce_keys [:codec, :sample_rate, :channels, :byte_order, :duration_ms, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          codec: :linear16,
          sample_rate: 48_000,
          channels: 1,
          byte_order: :little,
          duration_ms: non_neg_integer(),
          payload: binary()
        }
end
