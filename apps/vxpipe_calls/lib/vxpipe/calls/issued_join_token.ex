defmodule Vxpipe.Calls.IssuedJoinToken do
  @moduledoc "A join token returned once to its authenticated requester."

  @derive {Inspect, except: [:secret]}
  @enforce_keys [
    :id,
    :secret,
    :tenant_key,
    :call_id,
    :participant_key,
    :participant_ref,
    :issued_at,
    :expires_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          secret: String.t(),
          tenant_key: String.t(),
          call_id: String.t(),
          participant_key: String.t(),
          participant_ref: String.t(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t()
        }
end
