defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator
  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.RoomParticipantSupervisor
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  alias Vxpipe.CallEngine.RoomAuthority.{
    ParticipantLifecycle,
    ParticipantPreparation,
    EventPublisher,
    Startup,
    State
  }

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Runtime

  @spec commit(Request.t(), State.t()) ::
          {:reply, {:ok, map()} | {:error, :rejected | :unavailable}, State.t()}
  def commit(%Request{} = request, %State{} = state) do
    with :ok <- authorize(request, state),
         {:ok, %AgentDestination{} = destination} <- destination(request, state),
         {:ok, %ParticipantPreparation{} = preparation} <-
           ParticipantLifecycle.prepare(
             destination.command,
             state,
             agent_activation: destination.agent_activation
           ) do
      prepare_capabilities(request, destination, preparation, state)
    else
      {:error, :rejected} -> {:reply, {:error, :rejected}, state}
      {:error, _reason} -> {:reply, {:error, :unavailable}, state}
    end
  end

  @spec teardown_source(State.t(), pid(), Context.t()) :: State.t()
  def teardown_source(%State{} = state, capability, %Context{} = context)
      when is_pid(capability) do
    case Map.pop(state.pending_agent_teardowns, capability) do
      {%{participant_id: participant_id, participant_supervisor: supervisor}, pending}
      when participant_id == context.agent_participant_id ->
        _ =
          RoomParticipantSupervisor.stop_participant(
            state.snapshot.incarnation_id,
            supervisor
          )

        %{state | pending_agent_teardowns: pending}

      {_missing_or_stale, _pending} ->
        state
    end
  end

  defp authorize(
         %Request{} = request,
         %State{agent_transfer_runtime: %Runtime{} = runtime} = state
       ) do
    source = Map.get(runtime.plan.participants, request.source_definition_key)
    destination = Map.get(runtime.plan.participants, request.destination_definition_key)
    connection = Map.get(state.connections, request.connection_id)

    if state.snapshot.tenant_id == request.tenant_id and
         state.snapshot.room_id == request.room_id and
         state.snapshot.incarnation_id == request.incarnation_id and
         state.text_capability != nil and
         state.text_capability.participant_id == request.source_participant_id and
         state.text_capability.activation_id == request.source_activation_id and
         GenServer.whereis(state.text_capability.pid) == request.source_capability and
         source != nil and source.kind == :agent and
         source.participant_id == request.source_participant_id and
         source.activation_id == request.source_activation_id and
         request.destination_definition_key in source.transfers and
         destination != nil and destination.kind == :agent and
         destination.participant_id == request.destination_participant_id and
         not MapSet.member?(state.participant_ids, request.destination_participant_id) and
         connection != nil and connection.participant_id == request.caller_participant_id do
      :ok
    else
      {:error, :rejected}
    end
  end

  defp authorize(%Request{}, %State{}), do: {:error, :rejected}

  defp destination(request, %State{agent_transfer_runtime: %Runtime{} = runtime}) do
    participant = Map.fetch!(runtime.plan.participants, request.destination_definition_key)
    PlanStartup.agent_destination(runtime.plan, participant, runtime.startup_options)
  end

  defp prepare_capabilities(request, destination, preparation, state) do
    case Startup.prepare_text_to_speech(
           destination.text_to_speech,
           destination.participant.participant_id,
           state
         ) do
      {:ok, text_to_speech} ->
        commit_prepared(request, destination, preparation, text_to_speech, state)

      {:error, _reason} ->
        _ = ParticipantLifecycle.discard(preparation, state)
        {:reply, {:error, :unavailable}, state}
    end
  end

  defp commit_prepared(request, destination, preparation, text_to_speech, state) do
    {:ok, destination_snapshot, state} = ParticipantLifecycle.commit(preparation, state)
    source_text_to_speech = state.text_to_speech_capability
    source_supervisor = Map.fetch!(state.participant_supervisors, request.source_participant_id)

    destination_capability = %{
      activation_id: destination.participant.activation_id,
      module: AgentRuntimeCoordinator,
      monitor: nil,
      participant_id: destination_snapshot.participant_id,
      pid:
        Vxpipe.CallEngine.AgentActivationSupervisor.child_ref(
          destination.participant.activation_id,
          :coordinator
        )
    }

    pending_agent_teardowns =
      Map.put(state.pending_agent_teardowns, request.source_capability, %{
        participant_id: request.source_participant_id,
        participant_supervisor: source_supervisor
      })

    state = %{
      state
      | agent_turns: %{},
        pending_agent_teardowns: pending_agent_teardowns,
        text_capability: destination_capability,
        text_to_speech_capability: text_to_speech
    }

    _ = Startup.discard_text_to_speech(source_text_to_speech, state)

    result = %{
      "destination" => request.destination_definition_key,
      "status" => "completed"
    }

    state = publish_completed(request, result, state)
    {:reply, {:ok, result}, state}
  end

  defp publish_completed(request, result, state) do
    connection = Map.fetch!(state.connections, request.connection_id)

    event = %ToolCallCompleted{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.source_participant_id,
      source_participant_id: request.caller_participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      tool_call_id: request.tool_call_id,
      name: "transfer",
      result: result,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    state
    |> EventPublisher.publish(connection.pid, event)
    |> Map.update!(:background_tool_calls, &Map.delete(&1, request.tool_call_id))
    |> Map.update!(:next_sequence, &(&1 + 1))
  end
end
