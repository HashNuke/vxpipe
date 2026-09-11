defmodule Vxpipe.Gateway.TestRoomAudioOutputEngine do
  @moduledoc false

  def room_audio_output_configuration(%{store: store}) do
    Agent.get(store, fn state -> state.output_configuration end)
  end

  def subscribe_room_audio(%{store: store}, options) do
    subscriber = Keyword.fetch!(options, :subscriber)
    subscription_id = Keyword.fetch!(options, :id)

    Agent.get_and_update(store, fn state ->
      case Map.get(state, :subscribe_result, :ok) do
        :ok ->
          send(state.observer, {:test_room_audio_output_subscribed, subscription_id, subscriber})
          {{:ok, %{store: store, id: subscription_id}}, Map.put(state, :subscriber, subscriber)}

        {:error, reason} = error ->
          {error, Map.put(state, :subscribe_error, reason)}
      end
    end)
  end

  def register_room_audio_enforcer(%{store: store}, enforcer) do
    snapshot = Agent.get(store, fn state -> state.snapshot end)

    case GenServer.call(enforcer, {:vxpipe_apply_media_policy, snapshot}) do
      :ok -> {:ok, snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  def take_room_audio(%{store: store, id: subscription_id}, maximum_frames) do
    Agent.get_and_update(store, fn state ->
      {frames, remaining} = Enum.split(state.frames, maximum_frames)
      send(state.observer, {:test_room_audio_output_take, subscription_id, maximum_frames})
      {{:ok, frames}, %{state | frames: remaining}}
    end)
  end
end
