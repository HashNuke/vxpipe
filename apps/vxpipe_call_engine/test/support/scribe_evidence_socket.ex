defmodule Vxpipe.CallEngine.ScribeEvidenceSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.ElevenLabs.ScribeSocket

  def start_link(options) do
    {observer, transport} = Keyword.pop(Keyword.get(options, :transport_options, []), :observer)

    options =
      options
      |> Keyword.put(:transport_options, transport)
      |> Keyword.put(:connect_mode, :deferred)

    Socket.start_link(options, __MODULE__, %{
      owner: Keyword.fetch!(options, :owner),
      observer: observer,
      commit_strategy: :vad,
      keepalive_interval: 10_000,
      segment_hash: nil,
      partial_hash: nil
    })
  end

  def send_audio(socket, audio) do
    with :ok <- ScribeSocket.send_audio(socket, audio) do
      :telemetry.execute(
        [:vxpipe, :test, :scribe_outbound_audio],
        %{bytes: byte_size(audio)},
        %{socket: socket, digest: :crypto.hash(:sha256, audio)}
      )

      :ok
    end
  end

  defdelegate commit(socket), to: ScribeSocket
  @impl true
  defdelegate keepalive_frame(state), to: ScribeSocket

  @impl true
  def handle_frame({:text, payload} = frame, state) do
    state =
      case JSON.decode(payload) do
        {:ok, %{"message_type" => kind, "text" => text} = message}
        when kind in ["partial_transcript", "committed_transcript"] ->
          digest = :crypto.hash(:sha256, text)

          summary = %{
            kind: kind,
            bytes: byte_size(text),
            empty?: String.trim(text) == "",
            repeated_partial?: digest == state.partial_hash,
            equals_commit?: digest == state.segment_hash,
            fixture_telescope?: String.contains?(String.downcase(text), "telescope"),
            fixture_yes?: Regex.match?(~r/\byes\b/i, text),
            keys: Enum.sort(Map.keys(message))
          }

          send(state.observer, {:scribe_wire_evidence, summary})

          if kind == "committed_transcript",
            do: %{state | segment_hash: digest},
            else: %{state | partial_hash: digest}

        _other ->
          state
      end

    ScribeSocket.handle_frame(frame, state)
  end

  def handle_frame(frame, state), do: ScribeSocket.handle_frame(frame, state)
  @impl true
  defdelegate handle_disconnect(reason, state), to: ScribeSocket
  @impl true
  defdelegate handle_peer_close(status, state), to: ScribeSocket
end
