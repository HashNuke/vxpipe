defmodule Vxpipe.Gateway.Telephony.IncomingLegActivationContext do
  @moduledoc "Prepared incoming answer state retained by its owner before carrier submission."

  alias Vxpipe.CallEngine.Telephony.Answer
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, LegUsage, MediaBinding}

  @derive {Inspect, only: [:binding]}
  @enforce_keys [:binding, :service, :media_admission, :media_url, :request, :usage]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          binding: MediaBinding.t(),
          service: ConfiguredService.t(),
          media_admission: GenServer.server(),
          media_url: String.t(),
          request: Answer.t(),
          usage: LegUsage.t() | nil
        }
end
