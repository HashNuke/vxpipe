defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Preparation do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantPreparation

  @derive {Inspect, only: [:destination, :participant]}
  @enforce_keys [:destination, :participant, :text_to_speech]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          destination: AgentDestination.t(),
          participant: ParticipantPreparation.t(),
          text_to_speech: nil | map()
        }
end
