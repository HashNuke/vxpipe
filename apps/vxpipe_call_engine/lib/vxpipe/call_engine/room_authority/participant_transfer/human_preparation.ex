defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup.HumanDestination

  @derive {Inspect, only: [:destination]}
  @enforce_keys [:destination, :text_to_speech]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          destination: HumanDestination.t(),
          text_to_speech: map()
        }
end
