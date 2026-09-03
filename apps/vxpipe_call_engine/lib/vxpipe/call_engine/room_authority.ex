defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Capability.DeterministicText
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}
  alias Vxpipe.CallEngine.Event.TextOutput
  alias Vxpipe.CallEngine.{Error, Id, RoomCapabilitySupervisor, RoomParticipantSupervisor}
  alias Vxpipe.CallEngine.Room.Snapshot

  @call_timeout 5_000

  def start_link(options) do
    command = Keyword.fetch!(options, :command)
    name = via(command.tenant_id, command.room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @call_timeout)
  end

  def join_participant(room_authority, %JoinParticipant{} = command) do
    GenServer.call(room_authority, {:join_participant, command}, @call_timeout)
  end

  def attach_connection(
        room_authority,
        %AttachConnection{} = command,
        subscriber
      )
      when is_pid(subscriber) do
    GenServer.call(
      room_authority,
      {:attach_connection, command, subscriber},
      @call_timeout
    )
  end

  def send_text(room_authority, %SendText{} = command) do
    GenServer.call(room_authority, {:send_text, command}, @call_timeout)
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    state = %{
      connection_monitors: %{},
      connections: %{},
      next_sequence: 1,
      participant_monitors: %{},
      participant_ids: MapSet.new(),
      snapshot: build_snapshot(command, incarnation_id),
      text_capability: nil
    }

    case start_configured_agent(command, state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:join_participant, command}, _from, state) do
    if MapSet.member?(state.participant_ids, command.participant_id) do
      {:reply, {:error, participant_already_exists(command.participant_id)}, state}
    else
      admit_participant(command, state)
    end
  end

  def handle_call({:attach_connection, command, subscriber}, {caller, _tag}, state) do
    case authorize_attachment(command, caller, subscriber, state) do
      :ok -> put_connection(command, subscriber, state)
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:send_text, command}, {caller, _tag}, state) do
    case authorize_text(command, caller, state) do
      {:ok, capability} ->
        DeterministicText.respond(capability, command)
        {:reply, :ok, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_capability_text, capability, command, text}, state) do
    state = emit_text_output(capability, command, text, state)
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      cond do
        Map.has_key?(state.participant_monitors, monitor) ->
          remove_participant(monitor, state)

        Map.has_key?(state.connection_monitors, monitor) ->
          remove_connection(monitor, state)

        state.text_capability != nil and state.text_capability.monitor == monitor ->
          notify_connections(state.connections, :agent_unavailable)
          %{state | text_capability: nil}

        true ->
          state
      end

    {:noreply, state}
  end

  defp start_configured_agent(%CreateRoom{agent: nil}, state), do: {:ok, state}

  defp start_configured_agent(%CreateRoom{agent: :deterministic_text} = command, state) do
    with {:ok, join_command} <-
           JoinParticipant.new(
             tenant_id: command.tenant_id,
             actor_id: command.actor_id,
             room_id: command.room_id,
             participant_id: command.agent_participant_id,
             role: :agent,
             deadline: command.deadline
           ),
         {:ok, participant, state} <- start_participant(join_command, state),
         {:ok, capability} <-
           RoomCapabilitySupervisor.start_capability(
             state.snapshot.incarnation_id,
             self(),
             participant.participant_id
           ) do
      text_capability = %{
        monitor: Process.monitor(capability),
        participant_id: participant.participant_id,
        pid: capability
      }

      {:ok, %{state | text_capability: text_capability}}
    else
      _error -> {:error, :agent_start_failed}
    end
  end

  defp authorize_attachment(command, caller, subscriber, state) do
    cond do
      caller != subscriber ->
        {:error, connection_not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      not MapSet.member?(state.participant_ids, command.participant_id) ->
        {:error, participant_not_found(command.participant_id)}

      not agent_ready?(state) ->
        {:error, agent_not_ready()}

      Map.has_key?(state.connections, command.connection_id) ->
        {:error, connection_already_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp put_connection(command, subscriber, state) do
    monitor = Process.monitor(subscriber)

    connection = %{
      participant_id: command.participant_id,
      pid: subscriber
    }

    state = %{
      state
      | connection_monitors: Map.put(state.connection_monitors, monitor, command.connection_id),
        connections: Map.put(state.connections, command.connection_id, connection)
    }

    {:reply, :ok, state}
  end

  defp authorize_text(command, caller, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != caller or
          connection.participant_id != command.participant_id ->
        {:error, connection_not_attached(command.connection_id)}

      not agent_ready?(state) ->
        {:error, agent_not_ready()}

      true ->
        {:ok, state.text_capability.pid}
    end
  end

  defp agent_ready?(%{text_capability: nil}), do: false

  defp agent_ready?(state) do
    MapSet.member?(state.participant_ids, state.text_capability.participant_id)
  end

  defp emit_text_output(capability, command, text, state) do
    connection = Map.get(state.connections, command.connection_id)

    if state.text_capability != nil and state.text_capability.pid == capability and
         connection != nil and
         connection.participant_id == command.participant_id do
      event = %TextOutput{
        id: Id.generate(:event),
        sequence: state.next_sequence,
        tenant_id: state.snapshot.tenant_id,
        room_id: state.snapshot.room_id,
        incarnation_id: state.snapshot.incarnation_id,
        participant_id: state.text_capability.participant_id,
        source_participant_id: command.participant_id,
        connection_id: command.connection_id,
        command_id: command.id,
        correlation_id: command.correlation_id,
        text: text,
        aggregated_by: :sentence,
        will_be_spoken: false,
        occurred_at: DateTime.utc_now(:millisecond)
      }

      send(connection.pid, {:vxpipe_event, event})
      %{state | next_sequence: state.next_sequence + 1}
    else
      state
    end
  end

  defp admit_participant(command, state) do
    case start_participant(command, state) do
      {:ok, participant, state} ->
        {:reply, {:ok, participant}, state}

      {:error, :participant_already_exists} ->
        {:reply, {:error, participant_already_exists(command.participant_id)}, state}

      {:error, _reason} ->
        {:reply,
         {:error,
          Error.new(
            :room_start_failed,
            "The participant could not be admitted.",
            retryable: true
          )}, state}
    end
  end

  defp start_participant(command, state) do
    case RoomParticipantSupervisor.start_participant(state.snapshot.incarnation_id, command) do
      {:ok, participant_authority, participant} ->
        monitor = Process.monitor(participant_authority)

        state = %{
          state
          | participant_monitors:
              Map.put(state.participant_monitors, monitor, command.participant_id),
            participant_ids: MapSet.put(state.participant_ids, command.participant_id)
        }

        {:ok, participant, state}

      error ->
        error
    end
  end

  defp remove_participant(monitor, state) do
    {participant_id, participant_monitors} = Map.pop(state.participant_monitors, monitor)

    affected_connections =
      Map.filter(state.connections, fn {_connection_id, connection} ->
        connection.participant_id == participant_id
      end)

    notify_connections(affected_connections, :participant_unavailable)

    if state.text_capability != nil and
         state.text_capability.participant_id == participant_id do
      notify_connections(state.connections, :agent_unavailable)

      _ =
        RoomCapabilitySupervisor.stop_capability(
          state.snapshot.incarnation_id,
          state.text_capability.pid
        )
    end

    %{
      state
      | participant_monitors: participant_monitors,
        participant_ids: MapSet.delete(state.participant_ids, participant_id)
    }
  end

  defp remove_connection(monitor, state) do
    {connection_id, connection_monitors} = Map.pop(state.connection_monitors, monitor)

    %{
      state
      | connection_monitors: connection_monitors,
        connections: Map.delete(state.connections, connection_id)
    }
  end

  defp notify_connections(connections, reason) do
    Enum.each(connections, fn {_connection_id, connection} ->
      send(connection.pid, {:vxpipe_connection_unavailable, reason})
    end)
  end

  defp participant_already_exists(participant_id) do
    Error.new(
      :participant_already_exists,
      "The participant already exists.",
      details: %{"participant_id" => participant_id}
    )
  end

  defp participant_not_found(participant_id) do
    Error.new(
      :participant_not_found,
      "The participant does not exist.",
      details: %{"participant_id" => participant_id}
    )
  end

  defp connection_already_attached(connection_id) do
    Error.new(
      :connection_already_attached,
      "The connection is already attached.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp connection_not_attached(connection_id) do
    Error.new(
      :connection_not_attached,
      "The connection is not attached to this participant.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp room_incarnation_changed(incarnation_id) do
    Error.new(
      :room_incarnation_changed,
      "The room incarnation has changed.",
      details: %{"incarnation_id" => incarnation_id}
    )
  end

  defp agent_not_ready do
    Error.new(:agent_not_ready, "The room agent is not ready.", retryable: true)
  end

  defp build_snapshot(%CreateRoom{} = command, incarnation_id) do
    %Snapshot{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: command.actor_id,
      created_by_command_id: command.id
    }
  end

  defp via(tenant_id, room_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}}}
  end
end
