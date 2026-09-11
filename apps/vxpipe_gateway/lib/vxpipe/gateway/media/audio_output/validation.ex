defmodule Vxpipe.Gateway.Media.AudioOutput.Validation do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.Gateway.Media.AudioOutput.State

  @spec frame(AudioOutputFrame.t(), State.t()) :: :ok | {:error, atom()}
  def frame(%AudioOutputFrame{} = frame, %State{} = state) do
    cond do
      frame.connection_id != state.connection_id -> {:error, :wrong_connection}
      frame.tenant_id != state.identity.tenant_id -> {:error, :wrong_tenant}
      frame.room_id != state.identity.room_id -> {:error, :wrong_room}
      frame.incarnation_id != state.identity.incarnation_id -> {:error, :wrong_incarnation}
      frame.codec != :linear16 -> {:error, :unsupported_audio}
      frame.sample_rate != 48_000 -> {:error, :unsupported_audio}
      frame.channels != 1 -> {:error, :unsupported_audio}
      frame.byte_order != :little -> {:error, :unsupported_audio}
      not is_pid(frame.reply_to) -> {:error, :invalid_frame}
      not is_binary(frame.payload) or byte_size(frame.payload) == 0 -> {:error, :invalid_frame}
      true -> :ok
    end
  end

  @spec establish_turn(AudioOutputFrame.t(), State.t()) :: {:ok, State.t()} | {:error, :busy}
  def establish_turn(%AudioOutputFrame{} = frame, %State{current: nil} = state) do
    current = %{
      callback: frame.reply_to,
      command_id: frame.command_id,
      correlation_id: frame.correlation_id,
      incarnation_id: frame.incarnation_id,
      room_id: frame.room_id,
      source_participant_id: frame.participant_id,
      tenant_id: frame.tenant_id,
      finished?: false,
      frame_count: 0,
      last_progress_frames: 0,
      played_frames: 0,
      started?: false
    }

    {:ok, %{state | current: current}}
  end

  def establish_turn(%AudioOutputFrame{} = frame, %State{} = state) do
    current = state.current

    if current.correlation_id == frame.correlation_id and current.command_id == frame.command_id and
         current.callback == frame.reply_to and current.tenant_id == frame.tenant_id and
         current.room_id == frame.room_id and current.incarnation_id == frame.incarnation_id and
         current.source_participant_id == frame.participant_id and not current.finished? do
      {:ok, state}
    else
      {:error, :busy}
    end
  end

  @spec turn(term(), term(), State.t()) :: :ok | {:error, :wrong_turn}
  def turn(turn, callback, %State{current: current}) when not is_nil(current) do
    if current.correlation_id == turn and current.callback == callback do
      :ok
    else
      {:error, :wrong_turn}
    end
  end

  def turn(_turn, _callback, %State{}), do: {:error, :wrong_turn}
end
