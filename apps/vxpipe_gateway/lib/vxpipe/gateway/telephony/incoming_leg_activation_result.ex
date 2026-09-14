defmodule Vxpipe.Gateway.Telephony.IncomingLegActivationResult do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Submission
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, LegUsage, MediaBinding}

  @derive {Inspect, only: [:binding, :submission]}
  @enforce_keys [:binding, :media_url, :submission]
  defstruct @enforce_keys ++ [usage: nil, service: nil]

  @type t :: %__MODULE__{
          binding: MediaBinding.t(),
          media_url: String.t(),
          submission: Submission.t(),
          usage: LegUsage.t() | nil,
          service: ConfiguredService.t() | nil
        }
end
