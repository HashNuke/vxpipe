defmodule Vxpipe.Providers.Rime.TTSSocket do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.Rime.TTS

  @behaviour Socket

  def start_link(options) do
    Socket.start_link(options, __MODULE__, %{owner: Keyword.fetch!(options, :owner)})
  end

  def send_control(socket, payload), do: Socket.send_frame(socket, {:text, payload})
  def close(socket), do: Socket.close(socket, TTS.encode_clear())

  @impl true
  def handle_frame({:text, payload}, state) do
    case TTS.decode(payload) do
      {:audio, audio} ->
        reference = make_ref()
        send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, audio}})
        {:await, reference, state}

      :ignore ->
        {:ok, state}

      result ->
        send(state.owner, {:vxpipe_tts_transport, self(), {:control, result}})
        {:ok, state}
    end
  end

  def handle_frame(_frame, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, {:error, :invalid_message}}})
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end
end
