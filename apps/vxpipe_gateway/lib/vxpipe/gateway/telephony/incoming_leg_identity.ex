defmodule Vxpipe.Gateway.Telephony.IncomingLegIdentity do
  @moduledoc "Private carrier identity and initial usage retained before admission binding."

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, LegUsage, MediaBinding}

  @derive {Inspect, only: [:binding]}
  @enforce_keys [:binding, :service, :usage]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          binding: MediaBinding.t(),
          service: ConfiguredService.t(),
          usage: LegUsage.t() | nil
        }
end
