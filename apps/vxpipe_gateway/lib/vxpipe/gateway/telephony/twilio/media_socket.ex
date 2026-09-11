defmodule Vxpipe.Gateway.Telephony.Twilio.MediaSocket do
  @moduledoc false

  @behaviour WebSock

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.{Leg, MediaBinding}
  alias Vxpipe.Gateway.Telephony.Twilio.MediaDecoder

  @dispatch_timeout 5_000

  @impl true
  def init(%{binding: %MediaBinding{} = binding, clock: clock}) when is_function(clock, 0) do
    {:ok,
     %{
       binding: binding,
       clock: clock,
       leg_monitor: Process.monitor(binding.leg),
       stream_id: nil
     }}
  end

  @impl true
  def handle_in({message, opcode: :text}, state) do
    case MediaDecoder.decode(decoder_options(state), message) do
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

  def handle_info(_message, state), do: {:ok, state}

  defp dispatch(event, state) do
    case Leg.dispatch(state.binding.leg, event, @dispatch_timeout) do
      :ok -> {:ok, state}
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
