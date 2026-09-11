defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @derive {Inspect, only: []}
  @enforce_keys [:plan, :startup_options]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plan: ResolvedCallPlan.t(),
          startup_options: keyword()
        }
end
