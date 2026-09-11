defmodule Vxpipe.CallEngine.RoomMixer.State do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer.{Playout, SubscriptionCatalog, TimestampBuffer}

  @enforce_keys [
    :identity,
    :clock_origin_ms,
    :format,
    :recording_token,
    :playout,
    :policy,
    :buffer,
    :subscriptions,
    :source_sequences,
    :buffer_overflows,
    :policy_dropped_frames
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: %{tenant_id: String.t(), room_id: String.t(), incarnation_id: String.t()},
          clock_origin_ms: integer(),
          format: %{
            sample_rate: pos_integer(),
            channels: pos_integer(),
            frame_samples: pos_integer()
          },
          recording_token: nil | reference(),
          playout: Playout.t() | nil,
          policy: nil | Snapshot.t(),
          buffer: TimestampBuffer.t(),
          subscriptions: SubscriptionCatalog.t(),
          source_sequences: %{
            optional(TimestampBuffer.source_key()) => non_neg_integer()
          },
          buffer_overflows: non_neg_integer(),
          policy_dropped_frames: non_neg_integer()
        }
end
