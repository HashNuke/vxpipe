defmodule Vxpipe.Gateway.Telephony.Twilio.PlaybackClearer do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Media.PlaybackClearer

  @impl true
  def clear(options) when is_list(options) do
    socket_owner = Keyword.get(options, :socket_owner)
    stream_id = Keyword.get(options, :stream_id)

    if is_pid(socket_owner) and is_binary(stream_id) and byte_size(stream_id) > 0 do
      message = JSON.encode!(%{"event" => "clear", "streamSid" => stream_id})
      send(socket_owner, {:vxpipe_twilio_socket_send, message})
      :ok
    else
      {:error, :invalid_playback_target}
    end
  end

  def clear(_invalid), do: {:error, :invalid_playback_target}
end
