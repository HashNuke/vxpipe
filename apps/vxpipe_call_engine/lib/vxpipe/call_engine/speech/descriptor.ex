defmodule Vxpipe.CallEngine.Speech.Descriptor do
  @moduledoc "Validated public settings and evidence supplied by a speech provider."

  @enforce_keys [:kind, :settings, :format, :usage_identity, :readiness, :endpointing]
  defstruct @enforce_keys ++ [speech_start?: false, eager_end?: false, resume?: false]

  @type t :: %__MODULE__{
          kind: :stt,
          settings: struct(),
          format: map(),
          usage_identity: map(),
          readiness: :initialized | :provider_acknowledged,
          endpointing: :provider_semantic | :provider_gap | :external | :none,
          speech_start?: boolean(),
          eager_end?: boolean(),
          resume?: boolean()
        }
end
