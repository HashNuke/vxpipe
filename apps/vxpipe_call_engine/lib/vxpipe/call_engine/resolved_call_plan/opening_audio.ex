defmodule Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  @derive {Inspect, only: [:type]}
  @enforce_keys [:type, :text, :url, :text_to_speech]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          type: :text | :file_url,
          text: String.t() | nil,
          url: String.t() | nil,
          text_to_speech: CapabilitySelection.t() | nil
        }
end
