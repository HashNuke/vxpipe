defmodule Vxpipe.CallEngine.TestRoomTTSRequest do
  @moduledoc false
  def run(_config, text, consume) do
    send(__MODULE__.Observer, {:room_tts_request, self(), text})
    receive_audio(consume)
  end

  defp receive_audio(consume) do
    receive do
      {:audio, pcm} ->
        result = consume.(pcm)
        send(__MODULE__.Observer, {:room_tts_consumed, self(), result})
        if result == :ok, do: receive_audio(consume), else: result

      :complete ->
        :ok
    end
  end
end
