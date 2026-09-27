defmodule Vxpipe.CallEngine.TestGPTLiveHostedTransport do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.OpenAI.GPTLive

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    Socket.start_link(options, __MODULE__, %{owner: owner, observer: observer})
  end

  def send_control(socket, payload), do: Socket.send_frame(socket, {:text, payload})
  def close(socket), do: Socket.close(socket, JSON.encode!(GPTLive.close()))

  @impl true
  def handle_frame({:text, message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, message}})

    case JSON.decode(message) do
      {:ok, %{"type" => type}} when is_binary(type) ->
        send(state.observer, {:gpt_live_hosted_event, self(), type})

      _other ->
        send(state.observer, {:gpt_live_hosted_event, self(), :invalid_message})
    end

    {:ok, state}
  end

  def handle_frame({:binary, _message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, :invalid_binary_frame}})
    send(state.observer, {:gpt_live_hosted_event, self(), :invalid_binary_frame})
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :connection_lost}})
    send(state.observer, {:gpt_live_hosted_event, self(), :connection_lost})
    {:ok, state}
  end
end
