defmodule Vxpipe.CallEngine.RoomAuthority.UsageObservations do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.{State, TextCapability}
  alias Vxpipe.CallEngine.Usage.{ArchiveProjection, Observation}

  @spec record(State.t(), pid(), [Observation.t()]) :: State.t()
  def record(%State{} = state, capability, observations)
      when is_pid(capability) and is_list(observations) do
    with {:ok, source} <- source(state, capability),
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

  defp source(state, capability) do
    cond do
      TextCapability.current?(state, capability) ->
        {:ok,
         %{
           activation_id: state.text_capability.activation_id,
           participant_id: state.text_capability.participant_id
         }}

      Map.has_key?(state.pending_agent_teardowns, capability) ->
        pending = Map.fetch!(state.pending_agent_teardowns, capability)

        {:ok,
         %{
           activation_id:
             Recorder.participant_activation(state.archive_recorder, pending.participant_id),
           participant_id: pending.participant_id
         }}

      true ->
        {:error, :unauthorized}
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
end
