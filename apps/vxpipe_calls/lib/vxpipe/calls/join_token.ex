defmodule Vxpipe.Calls.JoinToken do
  @moduledoc false

  @derive {Inspect, except: [:digest]}
  @enforce_keys [
    :id,
    :tenant_key,
    :call_id,
    :participant_key,
    :participant_ref,
    :digest,
    :issued_at,
    :expires_at,
    :consumed_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          call_id: String.t(),
          participant_key: String.t(),
          participant_ref: String.t(),
          digest: binary(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t(),
          consumed_at: nil | DateTime.t()
        }
end
