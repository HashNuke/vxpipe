defmodule Vxpipe.CallEngine.ResolvedCallPlan.Capabilities do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  defstruct speech_to_text: nil,
            model_inference: nil,
            text_to_speech: nil,
            speech_to_speech: nil,
            output_speech_to_text: nil

  @type t :: %__MODULE__{
          speech_to_text: nil | CapabilitySelection.t(),
          model_inference: nil | CapabilitySelection.t(),
          text_to_speech: nil | CapabilitySelection.t(),
          speech_to_speech: nil | CapabilitySelection.t(),
          output_speech_to_text: nil | CapabilitySelection.t()
        }
end
