defmodule Vxpipe.CallEngine.Telephony.Dial do
  @moduledoc "A provider-neutral request to originate one authorized phone leg."

  @derive {Inspect, only: [:leg_id, :answering_machine_detection]}
  @enforce_keys [
    :leg_id,
    :from,
    :to,
    :callback_url,
    :media_url,
    :answering_machine_detection
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          leg_id: String.t(),
          from: String.t(),
          to: String.t(),
          callback_url: String.t(),
          media_url: String.t(),
          answering_machine_detection: :disabled | :detect
        }
end
