defmodule Vxpipe.Calls.AdmissionClaim do
  @moduledoc "An atomically accepted, participant-bound admission."

  alias Vxpipe.Calls.PreparedCall

  @enforce_keys [
    :call,
    :token_id,
    :participant_key,
    :participant_ref,
    :participant_id,
    :accepted_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call: PreparedCall.t(),
          token_id: String.t(),
          participant_key: String.t(),
          participant_ref: String.t(),
          participant_id: String.t(),
          accepted_at: DateTime.t()
        }
end
