defmodule Vxpipe.Calls.OperatorLoginChallenge do
  @moduledoc "A stored verifier for one bounded installation-operator login attempt."

  @enforce_keys [
    :token_digest,
    :code_verifier,
    :failed_attempts,
    :expires_at,
    :consumed_at,
    :issued_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          token_digest: binary(),
          code_verifier: binary(),
          failed_attempts: non_neg_integer(),
          expires_at: DateTime.t(),
          consumed_at: DateTime.t() | nil,
          issued_at: DateTime.t()
        }
end
