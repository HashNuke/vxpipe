defmodule Vxpipe.CallEngine.Telephony.OutboundLegHandle do
  @moduledoc false

  @derive {Inspect, only: [:connector]}
  @enforce_keys [:connector, :context, :owner, :reference]
  defstruct @enforce_keys ++ [submission_status: :accepted]

  @type t :: %__MODULE__{
          connector: module(),
          context: term(),
          owner: pid(),
          reference: term(),
          submission_status: :accepted | :unknown
        }
end
