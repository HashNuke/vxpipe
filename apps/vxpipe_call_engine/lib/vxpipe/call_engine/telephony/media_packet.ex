defmodule Vxpipe.CallEngine.Telephony.MediaPacket do
  @moduledoc "One authenticated provider media packet before room-clock normalization."

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :codec,
    :sample_rate,
    :channels,
    :sequence_number,
    :timestamp,
    :payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          codec: atom(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          sequence_number: non_neg_integer(),
          timestamp: non_neg_integer(),
          payload: binary()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = packet) do
    is_atom(packet.codec) and is_integer(packet.sample_rate) and packet.sample_rate > 0 and
      is_integer(packet.channels) and packet.channels > 0 and
      is_integer(packet.sequence_number) and packet.sequence_number >= 0 and
      is_integer(packet.timestamp) and packet.timestamp >= 0 and is_binary(packet.payload)
  end
end
