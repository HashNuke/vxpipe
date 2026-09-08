defmodule Vxpipe.CallEngine.ResolvedCallPlan.Capabilities do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection

  defstruct speech_to_text: nil, model_inference: nil, text_to_speech: nil

  @type t :: %__MODULE__{
          speech_to_text: nil | CapabilitySelection.t(),
          model_inference: nil | CapabilitySelection.t(),
          text_to_speech: nil | CapabilitySelection.t()
        }
end
