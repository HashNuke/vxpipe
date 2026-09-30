defmodule Vxpipe.Providers.ElevenLabs.AgentSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.ElevenLabs.AgentProtocol

  def start_link(options) do
    Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{
      owner: Keyword.fetch!(options, :owner)
    })
  end

  def initiate(socket), do: Socket.send_frame(socket, {:text, AgentProtocol.initiation()})
  def send_audio(socket, pcm), do: send_encoded(socket, AgentProtocol.audio(pcm))
  def pong(socket, id), do: send_encoded(socket, AgentProtocol.pong(id))

  def contextual_update(socket, text),
    do: send_encoded(socket, AgentProtocol.contextual_update(text))

  def user_message(socket, text), do: send_encoded(socket, AgentProtocol.user_message(text))

  def tool_result(socket, id, text, error?),
    do: send_encoded(socket, AgentProtocol.tool_result(id, text, error?))

  @impl true
  def handle_frame({:text, payload}, state) do
    case AgentProtocol.decode(payload) do
      {:ok, event} ->
        notify(state, {:event, event})

      {:error, reason} ->
        kind = AgentProtocol.message_kind(payload)
        reason = if kind == :unknown, do: reason, else: {reason, kind}
        notify(state, {:closed, reason})
    end
  end

  def handle_frame(_invalid, state), do: notify(state, {:closed, :invalid_frame})

  @impl true
  def handle_disconnect(_reason, state), do: notify(state, {:closed, :connection_lost})

  @impl true
  def handle_peer_close(status, state), do: notify(state, {:peer_closed, status})

  defp send_encoded(socket, {:ok, payload}), do: Socket.send_frame(socket, {:text, payload})
  defp send_encoded(_socket, {:error, reason}), do: {:error, reason}

  defp notify(state, event) do
    send(state.owner, {:vxpipe_elevenlabs_agent_transport, self(), event})
    {:ok, state}
  end
end
