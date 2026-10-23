defmodule Vxpipe.CallEngine.Speech.ContextTTSSocket do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Socket

  @behaviour Socket

  def start_link(options) do
    provider = Keyword.fetch!(options, :provider)
    owner = Keyword.fetch!(options, :owner)
    transport_options = Keyword.fetch!(options, :transport_options)

    Socket.start_link(
      Keyword.put(options, :connect_mode, :deferred),
      __MODULE__,
      %{
        owner: owner,
        provider: provider,
        keepalive_interval: Keyword.get(transport_options, :keepalive_interval, 20_000)
      }
    )
  end

  def send_control(socket, payload) when is_binary(payload),
    do: Socket.send_frame(socket, {:text, payload})

  def close(socket, nil), do: GenServer.stop(socket, :normal)
  def close(socket, goodbye) when is_binary(goodbye), do: Socket.close(socket, goodbye)

  @impl true
  def handle_frame({:text, payload}, %{provider: provider} = state) do
    case provider.decode_frame(payload) do
      {:ok, {:audio, context, audio}} ->
        forward_audio(state, context, audio, nil)

      {:ok, {:audio_final, context, audio}} ->
        forward_audio(state, context, audio, {:final, context})

      {:ok, {:final, context}} ->
        send(state.owner, {:vxpipe_tts_transport, self(), {:control, {:final, context}}})
        {:ok, state}

      {:ok, :ignore} ->
        {:ok, state}

      {:error, reason} ->
        send(state.owner, {:vxpipe_tts_transport, self(), {:control, {:error, reason}}})
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

  @impl true
  def handle_peer_close(_status, _reason, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, :peer_closed}})
    {:ok, state}
  end

  defp forward_audio(state, context, audio, final) do
    reference = make_ref()
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, {context, audio}}})

    if final,
      do: send(state.owner, {:vxpipe_tts_transport, self(), {:control, final}})

    {:await, reference, state}
  end
end
