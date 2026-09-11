defmodule Vxpipe.CallEngine.RoomMixer.Subscription do
  @moduledoc "An opaque handle for one bounded room-mixer output subscription."

  alias Vxpipe.CallEngine.RoomMixer

  @derive {Inspect, except: [:token]}
  @enforce_keys [
    :id,
    :mixer,
    :token,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :recipient_participant_id,
    :mode,
    :purpose
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          mixer: pid(),
          token: reference(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          recipient_participant_id: nil | String.t(),
          mode: Vxpipe.CallEngine.Media.MixedFrame.mode(),
          purpose: :participant | :recording
        }

  @spec take(t(), pos_integer()) ::
          {:ok, [Vxpipe.CallEngine.Media.MixedFrame.t()]} | {:error, term()}
  def take(%__MODULE__{} = subscription, maximum_frames) do
    RoomMixer.take(subscription, maximum_frames)
  end
end
