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
      archive_recorder =
        Enum.reduce(observations, state.archive_recorder, fn observation, recorder ->
          Recorder.internal_fact(
            recorder,
            :usage_observed,
            ArchiveProjection.attributes(observation)
          )
        end)

      %{state | archive_recorder: archive_recorder}
    else
      _unauthorized_or_invalid -> state
    end
  end

  def record(%State{} = state, _capability, _observations), do: state

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
end
