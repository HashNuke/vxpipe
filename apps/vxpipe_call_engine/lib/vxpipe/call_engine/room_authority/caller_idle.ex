defmodule Vxpipe.CallEngine.RoomAuthority.CallerIdle do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.{CallLifecycle, Id}

  alias Vxpipe.CallEngine.RoomAuthority.{
    OpeningAudio,
    State,
    TextCapability,
    TurnState
  }

  @notification """
  Vxpipe engine notification: the caller has provided no new input during the configured idle \
  interval. Follow your instructions to decide whether to speak, continue waiting silently, or \
  invoke a permitted tool. Do not infer that the caller disconnected.
  """

  @spec reconcile(State.t()) :: State.t()
  def reconcile(%State{call_lifecycle: nil} = state), do: state

  def reconcile(%State{} = state) do
    if eligible?(state) do
      _ = CallLifecycle.waiting(state.call_lifecycle)
    else
      _ = CallLifecycle.suspend(state.call_lifecycle)
    end

    state
  end

  @spec activity(State.t()) :: State.t()
  def activity(%State{call_lifecycle: nil} = state), do: state

  def activity(%State{} = state) do
    _ = CallLifecycle.activity(state.call_lifecycle)
    state
  end

  @spec notify(reference(), State.t()) :: State.t()
  def notify(token, %State{call_lifecycle: lifecycle} = state)
      when is_reference(token) and is_pid(lifecycle) do
    if eligible?(state) do
      start_notification(token, state)
    else
      _ = CallLifecycle.dismiss_idle(lifecycle, token)
      state
    end
  end

  defp start_notification(token, state) do
    with :ok <- CallLifecycle.claim_idle(state.call_lifecycle, token),
         {:ok, command} <- notification_command(state),
         :ok <- TextCapability.caller_idle(state.text_capability, command) do
      TurnState.put(state, command)
    else
      _not_started ->
        _ = CallLifecycle.dismiss_idle(state.call_lifecycle, token)
        state
    end
  end

  defp eligible?(state) do
    state.startup_ready? and
      MapSet.size(state.held_participant_ids) == 0 and
      OpeningAudio.admission(state.opening_audio) == :open and
      state.first_message.status == :completed and
      map_size(state.agent_turns) == 0 and
      map_size(state.background_tool_calls) == 0 and
      TextCapability.ready?(state) and
      waiting_connection(state) != nil
  end

  defp notification_command(state) do
    {connection_id, connection} = waiting_connection(state)

    SendText.new(
      id: Id.generate(:command),
      tenant_id: state.snapshot.tenant_id,
      actor_id: connection.actor_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id,
      correlation_id: Id.generate(:turn),
      content: @notification,
      run_immediately: false,
      audio_response: true,
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    )
  end

  defp waiting_connection(state) do
    Enum.find(state.connections, fn {_connection_id, connection} ->
      connection.participant_id == state.first_message.target_participant_id and
        no_active_speech?(connection)
    end)
  end

  defp no_active_speech?(%{speech_to_text: nil}), do: true
  defp no_active_speech?(%{speech_to_text: %{turn: nil}}), do: true
  defp no_active_speech?(_connection), do: false
end
