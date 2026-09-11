defmodule Vxpipe.CallEngine.RoomRecording.State do
  @moduledoc false

  @enforce_keys [
    :mixer,
    :mixer_monitor,
    :writer,
    :maximum_pull_frames,
    :streams,
    :accepted_chunks,
    :rejected_chunks
  ]
  defstruct @enforce_keys

  @type stream_state :: %{
          subscription: Vxpipe.CallEngine.RoomMixer.Subscription.t(),
          writer_handle: term(),
          next_sequence: non_neg_integer()
        }

  @type t :: %__MODULE__{
          mixer: pid(),
          mixer_monitor: reference(),
          writer: module(),
          maximum_pull_frames: pos_integer(),
          streams: %{optional(String.t()) => stream_state()},
          accepted_chunks: non_neg_integer(),
          rejected_chunks: non_neg_integer()
        }
end
