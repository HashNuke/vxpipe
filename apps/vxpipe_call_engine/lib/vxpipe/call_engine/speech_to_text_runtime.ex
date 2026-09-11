defmodule Vxpipe.CallEngine.SpeechToTextRuntime do
  @moduledoc false

  @derive {Inspect, only: [:call_id, :participant_id, :activation_id, :usage_provider]}
  @enforce_keys [
    :provider,
    :transport,
    :media_ingress,
    :call_id,
    :participant_id,
    :activation_id,
    :usage_provider
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          transport: {module(), keyword()},
          media_ingress: keyword(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t()
        }
end
