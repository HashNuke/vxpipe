defmodule Vxpipe.CallEngine.RoomAuthority.CallerIdle do
  @moduledoc false

  alias Vxpipe.CallEngine.CallLifecycle

  alias Vxpipe.CallEngine.RoomAuthority.{
    OpeningAudio,
    IdleNotification,
    IdleWait,
    State,
    TextCapability,
    TurnState
  }

  @spec reconcile(State.t()) :: State.t()
  def reconcile(%State{call_lifecycle: nil} = state), do: state

  def reconcile(%State{} = state) do
    state = IdleWait.reconcile(state)

    if eligible?(state) do
      _ = CallLifecycle.waiting(state.call_lifecycle)
    else
      _ = CallLifecycle.suspend(state.call_lifecycle)
    end

    state
  end

  @spec activity(State.t()) :: State.t()
  def activity(%State{} = state) do
    state = IdleWait.cancel(state, :participant_activity)
    if state.call_lifecycle, do: CallLifecycle.activity(state.call_lifecycle)
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
    state.startup_ready? and state.action_announcement == nil and
      MapSet.size(state.held_participant_ids) == 0 and
      OpeningAudio.admission(state.opening_audio) == :open and
      state.first_message.status == :completed and
      map_size(state.agent_turns) == 0 and
      state.idle_wait == nil and
      map_size(state.background_tool_calls) == 0 and
      TextCapability.ready?(state) and
      waiting_connection(state) != nil
  end

  defp notification_command(state) do
    {connection_id, _connection} = waiting_connection(state)
    IdleNotification.new(state, connection_id)
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
