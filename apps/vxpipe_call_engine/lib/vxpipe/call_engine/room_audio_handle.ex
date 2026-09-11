defmodule Vxpipe.CallEngine.RoomAudioHandle do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.RoomMixer

  @enforce_keys [:mixer, :media_policy_authority, :configuration]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          mixer: pid(),
          media_policy_authority: pid(),
          configuration: map()
        }

  @spec resolve(String.t()) :: {:ok, nil | t()} | {:error, :unavailable}
  def resolve(incarnation_id) when is_binary(incarnation_id) do
    mixer = RoomMixer.whereis(incarnation_id)
    media_policy_authority = MediaPolicyAuthority.whereis(incarnation_id)

    case {mixer, media_policy_authority} do
      {nil, nil} ->
        {:ok, nil}

      {mixer, media_policy_authority}
      when is_pid(mixer) and is_pid(media_policy_authority) ->
        with {:ok, configuration} <- RoomMixer.ingress_configuration(mixer) do
          {:ok,
           %__MODULE__{
             mixer: mixer,
             media_policy_authority: media_policy_authority,
             configuration: configuration
           }}
        end

      _incomplete ->
        {:error, :unavailable}
    end
  end

  @spec register_enforcer(t(), pid()) ::
          {:ok, Vxpipe.CallEngine.MediaPolicy.Snapshot.t()} | {:error, term()}
  def register_enforcer(%__MODULE__{} = handle, enforcer) when is_pid(enforcer) do
    MediaPolicyAuthority.register_enforcer(handle.media_policy_authority, enforcer)
  end

  @spec push(t(), NormalizedFrame.t()) :: :ok | {:error, term()}
  def push(%__MODULE__{} = handle, %NormalizedFrame{} = frame) do
    RoomMixer.push(handle.mixer, frame)
  end

  @spec subscribe(t(), keyword()) ::
          {:ok, Vxpipe.CallEngine.RoomMixer.Subscription.t()} | {:error, term()}
  def subscribe(%__MODULE__{} = handle, options) when is_list(options) do
    RoomMixer.subscribe(handle.mixer, options)
  end
end
