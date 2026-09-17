defmodule Vxpipe.Calls.IssuedOperatorLoginChallenge do
  @moduledoc "One-time operator login material returned only to the trusted issuer."

  @derive {Inspect, only: [:expires_at]}
  @enforce_keys [:token, :code, :expires_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          token: String.t(),
          code: String.t(),
          expires_at: DateTime.t()
        }
end
