defmodule Vxpipe.CallEngine.Media.AudioOutputFrame do
  @moduledoc false

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :codec,
    :sample_rate,
    :channels,
    :byte_order,
    :payload,
    :reply_to
  ]
  defstruct @enforce_keys ++ [audio_scope: :conversation, output_generation: 0]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          codec: :linear16,
          sample_rate: pos_integer(),
          channels: pos_integer(),
          byte_order: :little,
          payload: binary(),
          audio_scope: :conversation | :private | :mixed,
          output_generation: non_neg_integer(),
          reply_to: pid()
        }
end
