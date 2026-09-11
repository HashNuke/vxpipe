defmodule Vxpipe.CallEngine.Telephony.SendMedia do
  @moduledoc "One authorized room-mixer frame addressed to an exact phone leg."

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.Telephony.LegReference

  @derive {Inspect, only: [:leg, :frame]}
  @enforce_keys [:leg, :frame]
  defstruct @enforce_keys

  @type t :: %__MODULE__{leg: LegReference.t(), frame: MixedFrame.t()}
end
