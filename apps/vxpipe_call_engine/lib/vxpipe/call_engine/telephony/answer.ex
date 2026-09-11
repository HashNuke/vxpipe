defmodule Vxpipe.CallEngine.Telephony.Answer do
  @moduledoc "A provider-neutral request to answer an adopted phone leg with Vxpipe media."

  alias Vxpipe.CallEngine.Telephony.LegReference

  @enforce_keys [:leg, :media_url]
  defstruct @enforce_keys

  @type t :: %__MODULE__{leg: LegReference.t(), media_url: String.t()}
end
