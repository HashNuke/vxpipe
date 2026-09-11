defmodule Vxpipe.CallEngine.Telephony.EndLeg do
  @moduledoc "A provider-neutral request to end one exact known phone leg."

  alias Vxpipe.CallEngine.Telephony.LegReference

  @enforce_keys [:leg, :reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{leg: LegReference.t(), reason: atom()}
end
