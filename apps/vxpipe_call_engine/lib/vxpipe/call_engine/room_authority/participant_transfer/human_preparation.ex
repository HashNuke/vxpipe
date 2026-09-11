defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup.HumanDestination
  alias Vxpipe.CallEngine.Telephony.OutboundLegHandle

  @derive {Inspect, only: [:destination]}
  @enforce_keys [:destination, :outbound_leg, :text_to_speech]
  defstruct @enforce_keys ++ [outbound_leg_monitor: nil]

  @type t :: %__MODULE__{
          destination: HumanDestination.t(),
          outbound_leg: nil | OutboundLegHandle.t(),
          outbound_leg_monitor: nil | reference(),
          text_to_speech: map()
        }
end
