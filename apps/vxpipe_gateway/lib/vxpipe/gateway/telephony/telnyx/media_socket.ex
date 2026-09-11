defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaSocket do
  @moduledoc false

  @behaviour WebSock

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.Leg
  alias Vxpipe.Gateway.Telephony.MediaBinding
  alias Vxpipe.Gateway.Telephony.Telnyx.MediaDecoder

  @dispatch_timeout 5_000

  @impl true
  def init(%{binding: %MediaBinding{} = binding}) do
    monitor = Process.monitor(binding.leg)

    {:ok,
     %{
       binding: binding,
       decoder_options: decoder_options(binding),
       leg_monitor: monitor,
       stream_id: nil
     }}
  end

  @impl true
  def handle_in({message, opcode: :text}, state) do
    case MediaDecoder.decode(state.decoder_options, message) do
      {:ok, %Event{kind: :media_started, stream_id: stream_id} = event} ->
        dispatch(event, %{state | stream_id: stream_id})

      {:ok, %Event{} = event} ->
        dispatch(event, state)

      :ignore ->
        {:ok, state}

      {:error, :invalid_telnyx_media_message} ->
        invalid_message(state)
    end
  end

  def handle_in({_message, opcode: :binary}, state), do: invalid_message(state)

  @impl true
  def handle_info({:vxpipe_telnyx_socket_send, message}, state) when is_binary(message) do
    {:push, {:text, message}, state}
  end

  def handle_info({:DOWN, monitor, :process, leg, _reason}, state)
      when monitor == state.leg_monitor and leg == state.binding.leg do
    {:stop, :normal, {1000, "leg ended"}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  defp dispatch(event, state) do
    case Leg.dispatch(state.binding.leg, event, @dispatch_timeout) do
      :ok ->
        decoder_options = Keyword.put(state.decoder_options, :stream_id, state.stream_id)
        {:ok, %{state | decoder_options: decoder_options}}

      {:error, _reason} ->
        {:stop, :leg_unavailable, {1011, "leg unavailable"}, state}
    end
  end

  defp decoder_options(binding) do
    [
      leg_id: binding.client_state_leg_id,
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: binding.provider_call_session_id
    ]
  end

  defp invalid_message(state) do
    {:stop, :invalid_media_message, {1008, "invalid media message"}, state}
  end
end
