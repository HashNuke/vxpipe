defmodule Vxpipe.Console.Test.LiveDiagnosticsScribeSocket do
  @moduledoc "Real Scribe socket with bounded test-only event/PCM evidence."
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.ElevenLabs.ScribeSocket

  def start_link(options) do
    {observer, transport} = Keyword.pop(Keyword.fetch!(options, :transport_options), :observer)

    options =
      options
      |> Keyword.put(:transport_options, transport)
      |> Keyword.put(:connect_mode, :deferred)

    Socket.start_link(options, __MODULE__, %{
      owner: Keyword.fetch!(options, :owner),
      observer: observer,
      model: Keyword.fetch!(options, :model),
      commit_strategy: Keyword.fetch!(options, :commit_strategy),
      sent_samples: 0,
      keepalive_interval: 10_000,
      diagnostic_handoff: Keyword.get(options, :diagnostic_handoff)
    })
  end

  def send_audio(socket, audio) do
    with :ok <- ScribeSocket.send_audio(socket, audio) do
      :telemetry.execute([:vxpipe, :test, :live_scribe_pcm], %{bytes: byte_size(audio)}, %{})
      :ok
    end
  end

  defdelegate observe(socket, handoff), to: ScribeSocket
  defdelegate commit(socket), to: ScribeSocket
  defdelegate commit_with_receipt(socket), to: ScribeSocket
  @impl true
  defdelegate keepalive_frame(state), to: ScribeSocket

  @impl true
  defdelegate handle_sent(context, state), to: ScribeSocket

  @impl true
  def handle_frame({:text, payload} = frame, state) do
    result = ScribeSocket.handle_frame(frame, state)

    case Vxpipe.Providers.ElevenLabs.Scribe.decode_with_profile(
           payload,
           state.commit_strategy,
           state.model
         ) do
      {:ok, {:ready, _session, profile}} ->
        send(
          state.observer,
          {:live_scribe_profile, profile.missing, Map.keys(profile.acknowledged)}
        )

      _ ->
        :ok
    end

    case JSON.decode(payload) do
      {:ok, %{"message_type" => kind, "text" => text}}
      when kind in ["partial_transcript", "committed_transcript"] and is_binary(text) ->
        send(state.observer, {:live_scribe_event, kind, text == "", String.trim(text) == ""})

      _ ->
        :ok
    end

    result
  end

  def handle_frame(frame, state), do: ScribeSocket.handle_frame(frame, state)
  @impl true
  defdelegate handle_disconnect(reason, state), to: ScribeSocket
  @impl true
  defdelegate handle_peer_close(status, state), to: ScribeSocket
end
