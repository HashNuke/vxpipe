defmodule Vxpipe.CallEngine.RoomRecording.State do
  @moduledoc false

  @enforce_keys [
    :configuration,
    :mixer_monitor,
    :streams,
    :accepted_chunks,
    :rejected_chunks
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          configuration: Vxpipe.CallEngine.RoomRecording.Configuration.t(),
          mixer_monitor: reference(),
          streams: %{
            optional(String.t()) => Vxpipe.CallEngine.RoomRecording.SubscriptionState.t()
          },
          accepted_chunks: non_neg_integer(),
          rejected_chunks: non_neg_integer()
        }
end
