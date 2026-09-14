defmodule Vxpipe.CallEngine.RoomMixer.Subscription do
  @moduledoc "An opaque handle for one bounded room-mixer output subscription."

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RoomMixer

  @derive {Inspect, except: [:token, :prepared_policy_token]}
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
  defstruct @enforce_keys ++ [prepared_policy_token: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          mixer: pid(),
          token: reference(),
          prepared_policy_token: nil | reference(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          recipient_participant_id: nil | String.t(),
          mode:
            Vxpipe.CallEngine.Media.MixedFrame.mode()
            | :individual_tracks
            | {:individual_tracks, [String.t()]},
          purpose: :participant | :recording
        }

  @spec take(t(), pos_integer()) ::
          {:ok, [Vxpipe.CallEngine.Media.MixedFrame.t()]} | {:error, term()}
  def take(%__MODULE__{} = subscription, maximum_frames) do
    RoomMixer.take(subscription, maximum_frames)
  end

  @impl true
  def readiness(%__MODULE__{prepared_policy_token: token} = subscription)
      when is_reference(token) do
    RoomMixer.subscription_readiness(
      subscription.mixer,
      {subscription.id, :prepared_policy, token},
      subscription.token
    )
  end

  def readiness(%__MODULE__{} = subscription) do
    RoomMixer.subscription_readiness(subscription.mixer, subscription.id, subscription.token)
  end

  @impl true
  def readiness_binding(%Resource{} = resource) do
    RoomMixer.subscription_readiness(resource.instance, resource.binding, resource.generation)
  end
end
