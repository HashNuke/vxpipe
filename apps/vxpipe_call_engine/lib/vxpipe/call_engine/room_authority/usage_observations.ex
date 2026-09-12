defmodule Vxpipe.CallEngine.RoomAuthority.UsageObservations do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.{State, UsageSource}
  alias Vxpipe.CallEngine.Usage.{ArchiveProjection, Observation}

  @spec record(State.t(), pid(), [Observation.t()]) :: State.t()
  def record(%State{} = state, capability, observations)
      when is_pid(capability) and is_list(observations) do
    with {:ok, source} <- UsageSource.resolve(state, capability),
         true <- observations != [],
         true <- Enum.all?(observations, &authorized?(&1, source, state)) do
      archive(state, observations)
    else
      _unauthorized_or_invalid -> state
    end
  end

  def record(%State{} = state, _capability, _observations), do: state

  @spec record_telephony(State.t(), [Observation.t()]) :: State.t()
  def record_telephony(%State{} = state, observations) when is_list(observations) do
    if observations != [] and Enum.all?(observations, &authorized_telephony?(&1, state)) do
      archive(state, observations)
    else
      state
    end
  end

  defp authorized?(%Observation{} = observation, source, state) do
    attribution = observation.attribution

    observation.tenant_id == state.snapshot.tenant_id and
      Recorder.call_id?(state.archive_recorder, observation.call_id) and
      attribution.room_id == state.snapshot.room_id and
      attribution.incarnation_id == state.snapshot.incarnation_id and
      attribution.participant_id == source.participant_id and
      attribution.activation_id == source.activation_id
  end

  defp authorized?(_observation, _source, _state), do: false

  defp authorized_telephony?(%Observation{} = observation, state) do
    attribution = observation.attribution

    observation.capability == :telephony and
      observation.tenant_id == state.snapshot.tenant_id and
      Recorder.call_id?(state.archive_recorder, observation.call_id) and
      attribution.room_id == state.snapshot.room_id and
      attribution.incarnation_id == state.snapshot.incarnation_id and
      present?(attribution.participant_id) and is_nil(attribution.activation_id) and
      present?(attribution.leg_id)
  end

  defp authorized_telephony?(_observation, _state), do: false

  defp archive(state, observations) do
    archive_recorder =
      Enum.reduce(observations, state.archive_recorder, fn observation, recorder ->
        Recorder.internal_fact(
          recorder,
          :usage_observed,
          ArchiveProjection.attributes(observation)
        )
      end)

    %{state | archive_recorder: archive_recorder}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
