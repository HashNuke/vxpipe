defmodule Vxpipe.CallEngine.Readiness.RecordingOutputs do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Readiness.ResourceQuery
  alias Vxpipe.CallEngine.Recording.EgressReadiness

  def prepare(captured, connections) do
    required = captured.inventory.recording_participant_ids

    agents =
      for {_key, participant} <- captured.binding.plan.participants,
          participant.kind == :agent,
          MapSet.member?(required, participant.participant_id),
          do: participant.participant_id

    Enum.reduce_while(agents, {:ok, %{}, []}, fn agent, {:ok, tracks, resources} ->
      case prepare_agent(agent, captured, connections) do
        {:ok, bindings} ->
          modes =
            Enum.map(bindings, fn binding ->
              {:individual_track, agent, binding.connection_id, binding.track_id}
            end)

          {:cont,
           {:ok, Map.put(tracks, agent, modes), resources ++ Enum.map(bindings, & &1.resource)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp prepare_agent(agent, captured, connections) do
    policy = captured.candidate.snapshot

    listeners =
      Enum.filter(connections, fn {_id, graph} ->
        recipient = graph.identity.participant_id

        agent != recipient and
          Effective.audio_route_permitted?(policy.effective, agent, recipient)
      end)

    if listeners == [] do
      failure(agent)
    else
      Enum.reduce_while(listeners, {:ok, []}, fn {_id, graph}, {:ok, bindings} ->
        with [native] <- Enum.filter(graph.resources, &(&1.kind == :audio_output)),
             {:ok, binding} <-
               EgressReadiness.prepare(native, graph.identity, captured.room.room_mixer, policy) do
          {:cont, {:ok, [binding | bindings]}}
        else
          _unavailable -> {:halt, failure(agent)}
        end
      end)
    end
  end

  defp failure(agent),
    do: ResourceQuery.failure(:recording_output, {:participant, agent}, :output_track_unavailable)
end
