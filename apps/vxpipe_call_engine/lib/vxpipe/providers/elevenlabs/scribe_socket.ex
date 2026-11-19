defmodule Vxpipe.Providers.ElevenLabs.ScribeSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Diagnostics.ProviderTiming
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.ElevenLabs.Scribe

  def start_link(options) do
    with {:ok, public} <- Scribe.public_options(Keyword.take(options, [:model, :commit_strategy])) do
      Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{
        owner: Keyword.fetch!(options, :owner),
        model: public.model,
        commit_strategy: public.commit_strategy,
        keepalive_interval: 10_000,
        diagnostic_handoff: Keyword.get(options, :diagnostic_handoff)
      })
    end
  end

  def send_audio(socket, audio) do
    with {:ok, payload} <- Scribe.encode_audio(audio),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def observe(socket, handoff), do: Socket.observe(socket, handoff)

  def commit(socket), do: Socket.send_frame(socket, {:text, Scribe.commit()})

  @impl true
  def keepalive_frame(_state), do: {:text, Scribe.keepalive()}

  @impl true
  def handle_frame({:text, payload}, state) do
    receipt = ProviderTiming.stamp(Map.get(state, :diagnostic_handoff))

    case Scribe.decode(payload, state.commit_strategy, state.model) do
      {:ok, {kind, _text} = event} when kind in [:partial, :segment] and receipt != nil ->
        notify(state, {:event, event, receipt})

      {:ok, event} ->
        notify(state, {:event, event})

      {:error, reason} ->
        notify(state, {:closed, reason})
    end
  end

  def handle_frame(_invalid, state), do: notify(state, {:closed, :invalid_frame})

  @impl true
  def handle_disconnect(_reason, state), do: notify(state, {:closed, :connection_lost})

  @impl true
  def handle_peer_close(status, state), do: notify(state, {:peer_closed, status})

  defp notify(state, event) do
    send(state.owner, {:vxpipe_scribe_transport, self(), event})
    {:ok, state}
  end
end
