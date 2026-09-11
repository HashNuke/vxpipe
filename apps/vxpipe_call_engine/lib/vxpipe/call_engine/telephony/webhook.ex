defmodule Vxpipe.CallEngine.Telephony.Webhook do
  @moduledoc "Raw webhook bytes and normalized headers retained for signature verification."

  @derive {Inspect, only: [:received_at]}
  @enforce_keys [:headers, :body, :received_at]
  defstruct @enforce_keys ++ [url: nil, route_parameters: %{}]

  @type t :: %__MODULE__{
          headers: %{optional(String.t()) => String.t()},
          body: binary(),
          received_at: integer(),
          url: nil | String.t(),
          route_parameters: %{optional(String.t()) => String.t()}
        }
end
