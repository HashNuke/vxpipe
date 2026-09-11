defmodule Vxpipe.CallEngine.PlanStartup.HumanDestination do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant

  @derive {Inspect, only: [:participant]}
  @enforce_keys [:participant, :command]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          participant: Participant.t(),
          command: JoinParticipant.t()
        }
end
