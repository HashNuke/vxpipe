defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticSources do
  @moduledoc "Bounded current-room source candidates without prompts or provider configuration."
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Diagnostics.SourceSupervisor
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.RoomAuthority.State

  @doc "Coordinator-only bounded snapshot; never waits on a speech provider or model."
  def query(room_authority, cursor \\ nil, limit \\ 16) do
    GenServer.call(room_authority, {:diagnostic_sources, cursor, limit}, 250)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def read(%State{} = state, cursor, limit) do
    if (is_nil(cursor) or identifier?(cursor)) and is_integer(limit) and limit in 1..32,
      do: candidates(state, cursor, limit),
      else: {:error, :invalid_query}
  end

  defp candidates(
         %{
           participant_transfer_runtime: %{plan: plan},
           text_capability: %{participant_id: agent_id}
         } = state,
         cursor,
         limit
       ) do
    agent =
      Enum.find_value(plan.participants, fn {_, participant} ->
        if participant.participant_id == agent_id, do: participant
      end)

    identity = %{
      tenant_id: plan.tenant_id,
      call_id: plan.call_id,
      room_id: plan.room_id,
      incarnation_id: state.snapshot.incarnation_id
    }

    eligible? =
      state.snapshot.lifecycle == :open and state.startup_ready? and
        not match?(%{status: :pending}, state.outgoing_admission) and
        state.speech_to_speech_capability == nil and state.speech_to_speech_runtime == nil and
        MapSet.member?(state.participant_ids, agent_id) and
        not MapSet.member?(state.held_participant_ids, agent_id) and
        plan.tenant_id == state.snapshot.tenant_id and plan.room_id == state.snapshot.room_id and
        Enum.all?(Map.values(identity), &identifier?/1) and identifier?(agent_id) and
        SourceSupervisor.eligible_agent?(agent)

    if eligible? do
      human_ids =
        plan.participants
        |> Map.values()
        |> Enum.filter(&(&1.kind == :human))
        |> Enum.map(& &1.participant_id)
        |> MapSet.new()

      candidates =
        state.connections
        |> Enum.sort_by(&elem(&1, 0))
        |> Stream.filter(fn {id, connection} ->
          identifier?(id) and (cursor == nil or id > cursor) and
            current_source?(connection, state, human_ids)
        end)
        |> Enum.take(limit + 1)

      sources =
        candidates
        |> Enum.take(limit)
        |> Enum.map(fn {id, connection} ->
          %{
            connection_id: :binary.copy(id),
            participant_id: :binary.copy(connection.participant_id),
            capability: connection.speech_to_text.capability
          }
        end)

      # This is eligibility evidence for the observer factory, never a plan for call control.
      agent =
        struct(Participant,
          kind: :agent,
          participant_id: :binary.copy(agent_id),
          capabilities: %Capabilities{
            model_inference: struct(CapabilitySelection, kind: :model_inference)
          }
        )

      {:ok,
       %{
         identity: Map.new(identity, fn {key, value} -> {key, :binary.copy(value)} end),
         agent: agent,
         sources: sources,
         next_cursor: if(length(candidates) > limit, do: List.last(sources).connection_id)
       }}
    else
      {:error, :unsupported_call}
    end
  end

  defp candidates(_state, _cursor, _limit), do: {:error, :unsupported_call}

  defp current_source?(
         %{
           role: :human,
           admission: :main,
           participant_id: participant,
           speech_to_text: %{capability: capability}
         },
         state,
         human_ids
       ) do
    is_pid(capability) and node(capability) == node() and identifier?(participant) and
      MapSet.member?(human_ids, participant) and
      MapSet.member?(state.participant_ids, participant) and
      not MapSet.member?(state.held_participant_ids, participant)
  end

  defp current_source?(_connection, _state, _human_ids), do: false
  defp identifier?(value), do: is_binary(value) and byte_size(value) in 1..256
end
