defmodule Vxpipe.CallEngine.Integration.ElevenLabsScribePartialLatencyTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag skip: System.get_env("VXPIPE_MEASURE_SCRIBE_LATENCY") != "1"
  @moduletag timeout: 240_000

  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, Silero}
  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}

  # This is a measurement lane, not an assertion of a provider latency SLA.
  # Public synthetic fixtures only; credentials and connection data never leave the test.
  test "measure first nonempty partial against acoustic onset and Silero confirmation" do
    assert {:ok, model} = Silero.load()

    fixtures = [
      {"sentence", LiveFixture.pcm_path(), "telescope"},
      {"short", LiveFixture.short_pcm_path(), "yes"}
    ]

    for {name, path, expected} <- fixtures do
      for round <- 1..3 do
        # Vary onset phase and include enough preroll to probe initial buffering.
        leading_ms = round * 1_000

        audio =
          :binary.copy(<<0>>, leading_ms * 32) <>
            File.read!(path) <>
            :binary.copy(<<0>>, 96_000)

        reference = reference(model, audio) |> Map.put(:leading_silence_ms, leading_ms)
        IO.puts("SCRIBE_REFERENCE " <> JSON.encode!(Map.put(reference, :fixture, name)))

        assert {:ok, config} =
                 Scribe.new(
                   api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
                   language_code: "en",
                   commit_strategy: :vad
                 )

        id = make_ref()

        socket =
          start_supervised!(%{
            id: id,
            start:
              {ScribeSocket, :start_link,
               [
                 [
                   owner: self(),
                   connection: Scribe.connection_options(config),
                   commit_strategy: :vad,
                   transport_options: []
                 ]
               ]},
            restart: :temporary
          })

        assert_receive {:vxpipe_socket_connected, ^socket}, 15_000
        assert_receive {:vxpipe_scribe_transport, ^socket, {:event, {:ready, _}}}, 5_000

        for turn <- 1..2 do
          started = now()

          observed = %{
            first_partial_ms: nil,
            first_partial_text: nil,
            commit_ms: nil,
            committed_text: "",
            empty_partials: 0,
            max_send_lateness_ms: 0,
            silero_stream: Silero.new(),
            silero_boundary: ActivityBoundary.new(),
            silero_detected_ms: nil
          }

          observed = stream(socket, audio, started, 0, observed, model)
          observed = settle(socket, observed, started, now() + 5_000)
          assert String.downcase(observed.committed_text) =~ expected

          partial = observed.first_partial_ms

          row =
            Map.merge(
              reference,
              Map.drop(observed, [:committed_text, :silero_stream, :silero_boundary])
            )

          row =
            Map.merge(row, %{
              fixture: name,
              round: round,
              turn: turn,
              connection: if(turn == 1, do: "fresh", else: "reused"),
              partial_after_energy_ms: difference(partial, reference.energy_onset_ms),
              partial_after_silero_onset_ms: difference(partial, reference.silero_onset_ms),
              partial_after_silero_detection_ms: difference(partial, observed.silero_detected_ms)
            })

          IO.puts("SCRIBE_LATENCY " <> JSON.encode!(row))
        end

        stop_supervised!(id)
      end
    end
  end

  defp difference(nil, _reference), do: nil
  defp difference(value, reference), do: value - reference
  defp now, do: System.monotonic_time(:millisecond)

  defp reference(model, audio) do
    {_, _, events, _} =
      for <<frame::binary-size(1_024) <- audio>>,
        reduce: {Silero.new(), ActivityBoundary.new(), [], 0} do
        {stream, boundary, events, offset} ->
          assert {:ok, stream, [probability]} = Silero.push(stream, model, frame)
          assert {:ok, boundary, next} = ActivityBoundary.push(boundary, probability)
          events = events ++ Enum.map(next, fn {kind, onset} -> {kind, onset, offset + 512} end)
          {stream, boundary, events, offset + 512}
      end

    {_, onset, confirmed} = Enum.find(events, fn {kind, _, _} -> kind == :speech_started end)
    # Energy is an approximate acoustic onset: first 10 ms window above -40 dBFS RMS.
    energy =
      audio
      |> energy_windows(0)
      |> Enum.find(fn {_offset, rms} -> rms >= 0.01 end)
      |> elem(0)

    %{
      energy_onset_ms: div(energy, 16),
      silero_onset_ms: div(onset, 16),
      # Round to 20 ms capture boundaries, the same granularity as the stream.
      silero_detection_ms: div(confirmed + 319, 320) * 20,
      audio_duration_ms: div(byte_size(audio), 32)
    }
  end

  defp energy_windows(<<frame::binary-size(320), rest::binary>>, offset) do
    squares = for <<sample::signed-little-16 <- frame>>, do: :math.pow(sample / 32_768, 2)
    [{offset, :math.sqrt(Enum.sum(squares) / 160)} | energy_windows(rest, offset + 160)]
  end

  defp energy_windows(_tail, _offset), do: []

  defp stream(_socket, "", _started, _sent, observed, _model), do: observed

  defp stream(socket, audio, started, sent, observed, model) do
    size = min(640, byte_size(audio))
    <<chunk::binary-size(size), rest::binary>> = audio
    sent = sent + size
    due = started + div(sent, 32)
    observed = receive_until(socket, observed, started, due)
    assert :ok = ScribeSocket.send_audio(socket, chunk)
    observed = %{observed | max_send_lateness_ms: max(observed.max_send_lateness_ms, now() - due)}
    assert {:ok, silero_stream, probabilities} = Silero.push(observed.silero_stream, model, chunk)

    {boundary, detected} =
      Enum.reduce(
        probabilities,
        {observed.silero_boundary, observed.silero_detected_ms},
        fn probability, {boundary, detected} ->
          assert {:ok, boundary, events} = ActivityBoundary.push(boundary, probability)

          detected =
            if Enum.any?(events, fn {kind, _} -> kind == :speech_started end),
              do: detected || now() - started,
              else: detected

          {boundary, detected}
        end
      )

    observed = %{
      observed
      | silero_stream: silero_stream,
        silero_boundary: boundary,
        silero_detected_ms: detected
    }

    stream(socket, rest, started, sent, observed, model)
  end

  defp receive_until(socket, observed, started, due) do
    receive do
      {:vxpipe_scribe_transport, ^socket, {:event, event}} ->
        receive_until(socket, observe(observed, event, now() - started), started, due)

      {:vxpipe_scribe_transport, ^socket, _closed} ->
        flunk("Scribe closed during latency measurement")
    after
      max(0, due - now()) -> observed
    end
  end

  defp settle(_socket, %{commit_ms: time} = observed, _started, _deadline) when is_integer(time),
    do: observed

  defp settle(socket, observed, started, deadline) do
    observed = receive_until(socket, observed, started, deadline)
    assert is_integer(observed.commit_ms), "Scribe did not automatically commit the fixture"
    observed
  end

  defp observe(observed, {:partial, text}, elapsed) do
    cond do
      String.trim(text) == "" ->
        %{observed | empty_partials: observed.empty_partials + 1}

      is_nil(observed.first_partial_ms) ->
        %{observed | first_partial_ms: elapsed, first_partial_text: text}

      true ->
        observed
    end
  end

  defp observe(observed, {:segment, text}, elapsed),
    do: %{
      observed
      | commit_ms: observed.commit_ms || elapsed,
        committed_text: observed.committed_text <> " " <> text
    }
end
