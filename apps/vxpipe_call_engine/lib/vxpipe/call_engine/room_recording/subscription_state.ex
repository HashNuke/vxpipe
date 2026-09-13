defmodule Vxpipe.CallEngine.RoomRecording.SubscriptionState do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.Stream
  alias Vxpipe.CallEngine.RoomMixer.Subscription
  alias Vxpipe.CallEngine.RoomRecording.{Configuration, Output}

  @enforce_keys [:subscription, :target, :outputs]
  defstruct @enforce_keys ++ [required_modes: nil]

  @type t :: %__MODULE__{
          subscription: Subscription.t(),
          target: Configuration.target(),
          outputs: %{optional(Stream.mode()) => Output.t()}
        }
end
