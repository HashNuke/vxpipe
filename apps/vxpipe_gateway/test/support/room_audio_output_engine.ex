defmodule Vxpipe.Gateway.TestRoomAudioOutputEngine do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  def room_audio_output_configuration(%{store: store}) do
    Agent.get(store, fn state -> state.output_configuration end)
  end

  def subscribe_room_audio(%{store: store}, options) do
    subscriber = Keyword.fetch!(options, :subscriber)
    subscription_id = Keyword.fetch!(options, :id)

    Agent.get_and_update(store, fn state ->
      case Map.get(state, :subscribe_result, :ok) do
        :ok ->
          resource =
            Resource.new(
              :audio_subscription,
              {:participant, Keyword.fetch!(options, :recipient_participant_id)},
              __MODULE__,
              options,
              binding: subscription_id
            )

          send(state.observer, {:test_room_audio_output_subscribed, subscription_id, subscriber})

          state = Map.merge(state, %{subscriber: subscriber, readiness_resource: resource})
          {{:ok, %{store: store, id: subscription_id}}, state}

        {:error, reason} = error ->
          {error, Map.put(state, :subscribe_error, reason)}
      end
    end)
  end

  def room_audio_subscription_readiness(%{store: store}), do: readiness(store)

  def readiness(store) do
    Agent.get(store, fn state ->
      resource = state.readiness_resource
      {:participant, participant} = resource.scope
      interval = Snapshot.interval(state.snapshot, :audio_output, participant)
      status = if Map.get(state, :subscription_ready?, true), do: :ready, else: :preparing
      {:ok, %{resource | policy_interval: interval}, status}
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
