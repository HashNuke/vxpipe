defmodule Vxpipe.Gateway.Telephony.Twilio.MediaSocket do
  @moduledoc false

  @behaviour WebSock

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.SocketReadiness
  alias Vxpipe.Gateway.Telephony.{MediaBinding, PlaybackMarks, SocketDispatch}
  alias Vxpipe.Gateway.Telephony.Twilio.MediaDecoder

  @impl true
  def init(%{binding: %MediaBinding{} = binding, clock: clock}) when is_function(clock, 0) do
    {:ok,
     %{
       binding: binding,
       readiness_resource: SocketReadiness.new(binding),
       clock: clock,
       leg_monitor: Process.monitor(binding.leg),
       playback_marks: %PlaybackMarks{},
       dispatch: SocketDispatch.new(),
       stream_id: nil
     }}
  end

  @impl true
  def handle_in({message, opcode: :text}, state) do
    case MediaDecoder.decode(decoder_options(state), message) do
      {:ok, {:playback_mark, stream, name}} when stream == state.stream_id ->
        {:ok, %{state | playback_marks: PlaybackMarks.acknowledge(state.playback_marks, name)}}

      {:ok, %Event{kind: :media_started, stream_id: stream_id} = event}
      when is_nil(state.stream_id) ->
        dispatch(event, %{state | stream_id: stream_id})

      {:ok, %Event{kind: :media_started}} ->
        invalid_message(state)

      {:ok, %Event{} = event} ->
        dispatch(event, state)

      :ignore ->
        {:ok, state}

      {:error, :invalid_twilio_media_message} ->
        invalid_message(state)
    end
  end

  def handle_in({_message, opcode: :binary}, state), do: invalid_message(state)

  @impl true
  def handle_info({:vxpipe_phone_readiness, receiver, reference}, state) do
    :ok = SocketReadiness.reply(state, receiver, reference)
    {:ok, state}
  end

  def handle_info(
        {:vxpipe_playback_command, stream, action, receiver, request},
        %{stream_id: stream} = state
      )
      when is_binary(stream) do
    case PlaybackMarks.command(state.playback_marks, :twilio, stream, action, receiver, request) do
      {:ok, frames, marks} ->
        {:push, frames, %{state | playback_marks: marks}}

      {:error, reason} ->
        send(receiver, {:vxpipe_playback_ack, request, {:error, reason}})
        {:ok, state}
    end
  end

  def handle_info({:vxpipe_playback_command, _stream, _action, receiver, request}, state) do
    send(receiver, {:vxpipe_playback_ack, request, {:error, :wrong_stream}})
    {:ok, state}
  end

  def handle_info(
        {:vxpipe_twilio_socket_send, message},
        %{stream_id: stream_id} = state
      )
      when is_binary(message) and is_binary(stream_id) do
    {:push, {:text, message}, state}
  end

  def handle_info({:DOWN, monitor, :process, leg, _reason}, state)
      when monitor == state.leg_monitor and leg == state.binding.leg do
    {:stop, :normal, {1000, "leg ended"}, state}
  end

  def handle_info(message, state) do
    dispatch_result(SocketDispatch.response(state.dispatch, message), state)
  end

  defp dispatch(event, state) do
    dispatch_result(SocketDispatch.submit(state.dispatch, state.binding.leg, event), state)
  end

  defp dispatch_result(result, state) do
    case result do
      {:ok, dispatch} -> {:ok, %{state | dispatch: dispatch}}
      {:error, _reason} -> {:stop, :leg_unavailable, {1011, "leg unavailable"}, state}
    end
  end

  defp decoder_options(state) do
    binding = state.binding

    [
      leg_id: binding.client_state_leg_id,
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: binding.provider_call_session_id,
      stream_id: state.stream_id,
      received_at: state.clock.()
    ]
  end

  defp invalid_message(state) do
    {:stop, :invalid_media_message, {1008, "invalid media message"}, state}
  end
end
