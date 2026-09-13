defmodule Vxpipe.CallEngine.Media.PreparedConnection do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource

  @enforce_keys [:identity, :instance, :generation, :input_track, :resources]
  defstruct @enforce_keys

  @type input_track :: %{
          track_id: String.t(),
          codec: atom(),
          sample_rate: pos_integer(),
          channels: 1 | 2
        }

  @type t :: %__MODULE__{
          identity: map(),
          instance: pid(),
          generation: reference(),
          input_track: input_track() | nil,
          resources: [Resource.t()]
        }
end
