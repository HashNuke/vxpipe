defmodule Vxpipe.CallEngine.CallDefinition.CapabilitySelection do
  @moduledoc false

  @enforce_keys [:kind, :profile, :provider, :options]
  defstruct @enforce_keys

  @type kind :: :speech_to_text | :model_inference | :text_to_speech

  @type t :: %__MODULE__{
          kind: kind(),
          profile: String.t(),
          provider: atom(),
          options: map()
        }
end
