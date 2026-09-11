defmodule Vxpipe.CallEngine.TextToSpeechRuntime do
  @moduledoc false

  @derive {Inspect, only: [:maximum_requests, :asset_cache_identity]}
  @enforce_keys [:provider, :transport, :maximum_requests, :asset_cache_identity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          transport: {module(), keyword()},
          maximum_requests: pos_integer(),
          asset_cache_identity: map()
        }
end
