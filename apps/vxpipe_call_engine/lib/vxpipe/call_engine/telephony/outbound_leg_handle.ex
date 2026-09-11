defmodule Vxpipe.CallEngine.Telephony.OutboundLegHandle do
  @moduledoc false

  @derive {Inspect, only: [:connector]}
  @enforce_keys [:connector, :context, :owner, :reference]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          connector: module(),
          context: term(),
          owner: pid(),
          reference: term()
        }
end
