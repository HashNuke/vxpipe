defmodule Vxpipe.Gateway.Telephony.OutgoingLegReference do
  @moduledoc false

  @derive {Inspect, only: [:leg_id]}
  @enforce_keys [:leg, :leg_id, :supervisor]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          leg: pid(),
          leg_id: String.t(),
          supervisor: DynamicSupervisor.supervisor()
        }
end
