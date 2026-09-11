defmodule Vxpipe.Gateway.WebRTC.TransferSideband do
  @moduledoc false

  alias ExWebRTC.PeerConnection
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Sideband.{Codec, TransferControl}
  alias Vxpipe.Gateway.WebRTC.MainMedia

  @spec handle_data(binary(), map()) :: {:ok, map()}
  def handle_data(payload, state) do
    case Codec.handle(payload) do
      {:reply, reply} ->
        send_data(reply, state)
        {:ok, state}

      {:command, {:accept, input}} ->
        accept(input, state)

      :ignore ->
        {:ok, state}
    end
  end

  @spec channel_opened(map()) :: map()
  def channel_opened(
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          },
          transfer_preparation_sent?: false
        } = state
      ) do
    {:ok, message} = Codec.encode_preparation(attempt_id, state.session.participant_id)
    send_data(message, state)
    %{state | transfer_preparation_sent?: true}
  end

  def channel_opened(state), do: state

  @spec media_connected(map()) :: {:ok, map()} | {:stop, map()}
  def media_connected(
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          },
          transfer_media_ready?: false
        } = state
      ) do
    case submit(:media_ready, attempt_id, state) do
      :ok -> {:ok, %{state | transfer_media_ready?: true}}
      {:error, :rejected} -> {:stop, state}
    end
  end

  def media_connected(state), do: {:ok, state}

  @spec activate_main_media(String.t(), ConnectionAttachment.t(), map()) ::
          {:ok, map()} | {:stop, map()}
  def activate_main_media(
        attempt_id,
        %ConnectionAttachment{admission: :main} = attachment,
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          }
        } = state
      ) do
    case MainMedia.activate(
           state.connection_id,
           attachment,
           state.session,
           state.peer_connection,
           state.output_track_id,
           state.audio_jitter_latency_ms
         ) do
      {:ok, room_audio_ingress, room_audio_egress} ->
        state = %{
          state
          | attachment: attachment,
            room_audio_egress: room_audio_egress,
            room_audio_ingress: room_audio_ingress
        }

        send_active(attempt_id, state)
        {:ok, state}

      {:error, _reason} ->
        {:stop, state}
    end
  end

  defp accept(input, state) do
    case submit(:accept, input.attempt_id, state) do
      :ok ->
        {:ok, state}

      {:error, :rejected} ->
        input.id
        |> Codec.encode_error()
        |> send_data(state)

        {:ok, state}
    end
  end

  defp submit(action, attempt_id, state) do
    TransferControl.submit(
      action,
      attempt_id,
      state.connection_id,
      state.session,
      state.attachment
    )
  end

  defp send_active(attempt_id, state) do
    {:ok, message} = Codec.encode_active(attempt_id)
    send_data(message, state)
  end

  defp send_data(message, state) do
    :ok = PeerConnection.send_data(state.peer_connection, state.sideband_channel_ref, message)
  end
end
