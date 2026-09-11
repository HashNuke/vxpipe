defmodule Vxpipe.CallEngine.TextToSpeechRuntime do
  @moduledoc false

  @derive {Inspect, only: [:maximum_requests, :asset_cache_identity]}
  @enforce_keys [
    :provider,
    :transport,
    :maximum_requests,
    :asset_cache_identity,
    :call_id,
    :participant_id,
    :activation_id,
    :usage_provider
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          transport: {module(), keyword()},
          maximum_requests: pos_integer(),
          asset_cache_identity: map(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t(),
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t()
        }
end
