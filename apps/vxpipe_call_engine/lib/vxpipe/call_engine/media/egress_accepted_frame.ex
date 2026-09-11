defmodule Vxpipe.CallEngine.Media.EgressAcceptedFrame do
  @moduledoc """
  One PCM frame accepted by a live transport for direct egress.

  Acceptance means the transport boundary accepted the frame. It does not prove
  that a remote participant played or heard it.
  """

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :source_participant_id,
    :connection_id,
    :sample_rate,
    :channels,
    :payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_participant_id: String.t(),
          connection_id: String.t(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          payload: binary()
        }
end
