defmodule Vxpipe.CallEngine.RoomAuthority.ConnectionLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.{Error, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.RoomAuthority.{OpeningAudio, State, TextCapability}

  @spec attach(struct(), pid(), pid(), pid() | nil, reference(), State.t()) ::
          {:reply, {:ok, atom(), term()} | {:error, Error.t()}, State.t()}
  def attach(command, caller, subscriber, output_sink, room_monitor, %State{} = state) do
    case authorize_attachment(command, caller, subscriber, state) do
      :ok -> put(command, subscriber, output_sink, room_monitor, state)
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  @spec attach_transfer_preparation(
          struct(),
          pid(),
          pid(),
          pid() | nil,
          reference(),
          String.t(),
          State.t()
        ) :: {:reply, tuple() | {:error, Error.t()}, State.t()}
  def attach_transfer_preparation(
        command,
        caller,
        subscriber,
        output_sink,
        room_monitor,
        attempt_id,
        %State{} = state
      ) do
    case authorize_transfer_attachment(command, caller, subscriber, state) do
      :ok ->
        put_transfer_preparation(
          command,
          subscriber,
          output_sink,
          room_monitor,
          attempt_id,
          state
        )

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @spec promote_transfer(String.t(), State.t()) ::
          {:ok, map(), State.t()} | {:error, :unavailable}
  def promote_transfer(attempt_id, %State{} = state) when is_binary(attempt_id) do
    case Enum.find(state.connections, fn {_connection_id, connection} ->
           connection.admission == :transfer_preparation and
             connection.transfer_attempt_id == attempt_id
         end) do
      {connection_id, connection} ->
        promoted = %{connection | admission: :main, transfer_attempt_id: nil}

        archive_recorder =
          ArchiveRecorder.connection_attached(
            state.archive_recorder,
            connection.attach_command,
            connection.role
          )

        state = %{
          state
          | archive_recorder: archive_recorder,
            connections: Map.put(state.connections, connection_id, promoted)
        }

        {:ok, promoted, state}

      nil ->
        {:error, :unavailable}
    end
  end

  @spec discard_transfer(String.t(), atom(), State.t()) :: State.t()
  def discard_transfer(attempt_id, reason, %State{} = state)
      when is_binary(attempt_id) and is_atom(reason) do
    case Enum.find(state.connections, fn {_connection_id, connection} ->
           connection.admission == :transfer_preparation and
             connection.transfer_attempt_id == attempt_id
         end) do
      {connection_id, connection} ->
        send(connection.pid, {:vxpipe_connection_unavailable, reason})
        remove_by_id(connection_id, state, reason: reason)

      nil ->
        state
    end
  end

  @spec bind_speech_to_text(struct(), pid(), pid(), pid(), pid(), State.t()) ::
          {:reply, :ok | {:error, Error.t()}, State.t()}
  def bind_speech_to_text(command, caller, subscriber, capability, ingress, %State{} = state) do
    case authorize_speech_to_text_binding(command, caller, subscriber, state) do
      :ok -> bind_with_media_policy(command, capability, ingress, state)
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  @spec detach(struct(), pid(), pid(), State.t()) ::
          {:reply, :ok | {:error, Error.t()}, State.t()}
  def detach(command, caller, subscriber, %State{} = state) do
    case authorize_detachment(command, caller, subscriber, state) do
      :ok ->
        state = remove_by_id(command.connection_id, state, command_id: command.id)
        {:reply, :ok, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @spec authorize_text(struct(), pid(), State.t()) :: {:ok, map()} | {:error, Error.t()}
  def authorize_text(command, caller, %State{} = state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != caller or
          connection.participant_id != command.participant_id ->
        {:error, not_attached(command.connection_id)}

      connection.admission != :main ->
        {:error, not_attached(command.connection_id)}

      OpeningAudio.admission(state.opening_audio) != :open ->
        {:error, opening_audio_in_progress()}

      not TextCapability.ready?(state) ->
        {:error, agent_not_ready()}

      true ->
        {:ok, state.text_capability}
    end
  end

  @spec remove(reference(), term(), State.t()) :: State.t()
  def remove(monitor, reason, %State{} = state) do
    {connection_id, connection_monitors} = Map.pop(state.connection_monitors, monitor)
    state = %{state | connection_monitors: connection_monitors}
    remove_by_id(connection_id, state, reason: reason)
  end

  @spec speech_to_text_unavailable(pid(), map(), State.t()) :: State.t()
  def speech_to_text_unavailable(capability, identity, %State{} = state) do
    case authorized_speech_to_text(capability, identity, state) do
      {:ok, connection_id, _connection} -> clear_speech_to_text(connection_id, true, state)
      :error -> state
    end
  end

  @spec remove_unavailable_speech_to_text(reference(), State.t()) :: State.t()
  def remove_unavailable_speech_to_text(monitor, %State{} = state) do
    case Map.fetch(state.speech_to_text_monitors, monitor) do
      {:ok, connection_id} -> clear_speech_to_text(connection_id, true, state)
      :error -> state
    end
  end

  @spec authorized_speech_to_text(pid(), map(), State.t()) ::
          {:ok, String.t(), map()} | :error
  def authorized_speech_to_text(capability, identity, %State{} = state) do
    connection_id = Map.get(identity, :connection_id)
    connection = Map.get(state.connections, connection_id)

    if connection != nil and connection.speech_to_text != nil and
         connection.speech_to_text.capability == capability and
         connection.participant_id == Map.get(identity, :participant_id) and
         state.snapshot.tenant_id == Map.get(identity, :tenant_id) and
         state.snapshot.room_id == Map.get(identity, :room_id) and
         state.snapshot.incarnation_id == Map.get(identity, :incarnation_id) do
      {:ok, connection_id, connection}
    else
      :error
    end
  end

  @spec notify(map(), atom()) :: :ok
  def notify(connections, reason) do
    Enum.each(connections, fn {_connection_id, connection} ->
      send(connection.pid, {:vxpipe_connection_unavailable, reason})
    end)
  end

  @spec open_inputs(State.t()) :: State.t()
  def open_inputs(%State{} = state) do
    Enum.each(state.connections, fn {_connection_id, connection} ->
      open_connection_input(connection)
    end)

    state
  end

  defp authorize_attachment(command, caller, subscriber, state) do
    cond do
      caller != subscriber ->
        {:error, not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      not MapSet.member?(state.participant_ids, command.participant_id) ->
        {:error, participant_not_found(command.participant_id)}

      not attachment_ready?(state) ->
        {:error, agent_not_ready()}

      Map.has_key?(state.connections, command.connection_id) ->
        {:error, already_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp attachment_ready?(%State{text_capability_required?: false}), do: true
  defp attachment_ready?(%State{} = state), do: TextCapability.ready?(state)

  defp put(command, subscriber, output_sink, room_monitor, state) do
    monitor = Process.monitor(subscriber)
    role = Map.fetch!(state.participant_roles, command.participant_id)

    connection = %{
      admission: :main,
      actor_id: command.actor_id,
      attach_command: command,
      participant_id: command.participant_id,
      pid: subscriber,
      output_sink: output_sink,
      role: role,
      room_monitor: room_monitor,
      transfer_attempt_id: nil,
      speech_to_text: nil
    }

    state = %{
      state
      | connection_monitors: Map.put(state.connection_monitors, monitor, command.connection_id),
        connections: Map.put(state.connections, command.connection_id, connection)
    }

    archive_recorder = ArchiveRecorder.connection_attached(state.archive_recorder, command, role)
    state = %{state | archive_recorder: archive_recorder}
    runtime = selected_speech_to_text_runtime(command.participant_id, state)

    {input_mode, output_mode} = media_modes(role, state)
    {:reply, {:ok, role, runtime, :main, input_mode, output_mode, nil}, state}
  end

  defp put_transfer_preparation(
         command,
         subscriber,
         output_sink,
         room_monitor,
         attempt_id,
         state
       ) do
    monitor = Process.monitor(subscriber)

    connection = %{
      admission: :transfer_preparation,
      actor_id: command.actor_id,
      attach_command: command,
      participant_id: command.participant_id,
      pid: subscriber,
      output_sink: output_sink,
      role: :human,
      room_monitor: room_monitor,
      speech_to_text: nil,
      transfer_attempt_id: attempt_id
    }

    state = %{
      state
      | connection_monitors: Map.put(state.connection_monitors, monitor, command.connection_id),
        connections: Map.put(state.connections, command.connection_id, connection)
    }

    {:reply, {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, attempt_id}, state}
  end

  defp media_modes(:monitor, _state), do: {:disabled, :full_mix}

  defp media_modes(_role, %{text_capability_required?: true}),
    do: {:enabled, :direct}

  defp media_modes(_role, %{text_capability_required?: false}),
    do: {:enabled, :mix_minus}

  defp selected_speech_to_text_runtime(_participant_id, %{speech_to_text_runtime: :application}),
    do: :application

  defp selected_speech_to_text_runtime(participant_id, state) do
    Map.get(state.speech_to_text_runtime, participant_id)
  end

  defp authorize_speech_to_text_binding(command, caller, subscriber, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      caller != subscriber ->
        {:error, not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != subscriber or
          connection.participant_id != command.participant_id ->
        {:error, not_attached(command.connection_id)}

      connection.admission != :main ->
        {:error, speech_to_text_not_bindable(command.connection_id)}

      connection.role != :human or connection.speech_to_text != nil ->
        {:error, speech_to_text_not_bindable(command.connection_id)}

      true ->
        :ok
    end
  end

  defp authorize_detachment(command, caller, subscriber, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      caller != subscriber ->
        {:error, not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != subscriber or
          connection.participant_id != command.participant_id ->
        {:error, not_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp bind_with_media_policy(command, capability, ingress, state) do
    case register_speech_to_text_enforcers(state.media_policy_authority, capability, ingress) do
      :ok -> bind(command, capability, ingress, state)
      {:error, _reason} -> {:reply, {:error, speech_to_text_policy_unavailable()}, state}
    end
  end

  defp register_speech_to_text_enforcers(nil, _capability, _ingress), do: :ok

  defp register_speech_to_text_enforcers(authority, capability, ingress) do
    with {:ok, _snapshot} <- MediaPolicyAuthority.register_enforcer(authority, ingress),
         {:ok, _snapshot} <- MediaPolicyAuthority.register_enforcer(authority, capability) do
      :ok
    end
  end

  defp bind(command, capability, ingress, state) do
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    connection = Map.fetch!(state.connections, command.connection_id)

    speech_to_text = %{
      capability: capability,
      capability_monitor: capability_monitor,
      ingress: ingress,
      ingress_monitor: ingress_monitor,
      turn: nil
    }

    connection = %{connection | speech_to_text: speech_to_text}

    speech_to_text_monitors =
      state.speech_to_text_monitors
      |> Map.put(capability_monitor, command.connection_id)
      |> Map.put(ingress_monitor, command.connection_id)

    state = %{
      state
      | connections: Map.put(state.connections, command.connection_id, connection),
        speech_to_text_monitors: speech_to_text_monitors
    }

    if OpeningAudio.admission(state.opening_audio) == :open do
      :ok = Ingress.open(ingress)
    end

    {:reply, :ok, state}
  end

  defp remove_by_id(nil, state, _attributes), do: state

  defp remove_by_id(connection_id, state, attributes) do
    connection = Map.get(state.connections, connection_id)
    state = clear_speech_to_text(connection_id, false, state)
    {monitor, connection_monitors} = pop_monitor(connection_id, state)

    if monitor != nil do
      Process.demonitor(monitor, [:flush])
    end

    state = %{
      state
      | connection_monitors: connection_monitors,
        connections: Map.delete(state.connections, connection_id)
    }

    if connection == nil or connection.admission != :main do
      state
    else
      archive_recorder =
        ArchiveRecorder.connection_detached(
          state.archive_recorder,
          connection_id,
          connection,
          attributes
        )

      %{state | archive_recorder: archive_recorder}
    end
  end

  defp authorize_transfer_attachment(command, caller, subscriber, state) do
    cond do
      caller != subscriber ->
        {:error, not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      Map.has_key?(state.connections, command.connection_id) ->
        {:error, already_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp clear_speech_to_text(connection_id, notify?, state) do
    connection = Map.get(state.connections, connection_id)

    if connection != nil and connection.speech_to_text != nil do
      speech_to_text = connection.speech_to_text
      Process.demonitor(speech_to_text.capability_monitor, [:flush])
      Process.demonitor(speech_to_text.ingress_monitor, [:flush])

      :ok =
        RoomCapabilitySupervisor.stop_speech_to_text(
          state.snapshot.incarnation_id,
          speech_to_text.capability,
          speech_to_text.ingress
        )

      connection = %{connection | speech_to_text: nil}

      speech_to_text_monitors =
        state.speech_to_text_monitors
        |> Map.delete(speech_to_text.capability_monitor)
        |> Map.delete(speech_to_text.ingress_monitor)

      if notify? do
        send(connection.pid, {:vxpipe_connection_unavailable, :speech_to_text_unavailable})
      end

      %{
        state
        | connections: Map.put(state.connections, connection_id, connection),
          speech_to_text_monitors: speech_to_text_monitors
      }
    else
      state
    end
  end

  defp pop_monitor(connection_id, state) do
    case Enum.find(state.connection_monitors, fn {_monitor, id} -> id == connection_id end) do
      {monitor, _connection_id} ->
        {monitor, Map.delete(state.connection_monitors, monitor)}

      nil ->
        {nil, state.connection_monitors}
    end
  end

  defp participant_not_found(participant_id) do
    Error.new(
      :participant_not_found,
      "The participant does not exist.",
      details: %{"participant_id" => participant_id}
    )
  end

  defp already_attached(connection_id) do
    Error.new(
      :connection_already_attached,
      "The connection is already attached.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp not_attached(connection_id) do
    Error.new(
      :connection_not_attached,
      "The connection is not attached to this participant.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp speech_to_text_not_bindable(connection_id) do
    Error.new(
      :speech_to_text_not_bindable,
      "Speech-to-text cannot be bound to this connection.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp speech_to_text_policy_unavailable do
    Error.new(
      :speech_to_text_policy_unavailable,
      "Speech-to-text media policy could not be applied.",
      retryable: true
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

  defp opening_audio_in_progress do
    Error.new(
      :opening_audio_in_progress,
      "Caller input is not admitted until the opening audio finishes.",
      retryable: true
    )
  end

  defp open_connection_input(%{speech_to_text: %{ingress: ingress}}) do
    _ = Ingress.open(ingress)
    :ok
  end

  defp open_connection_input(_connection), do: :ok
end
