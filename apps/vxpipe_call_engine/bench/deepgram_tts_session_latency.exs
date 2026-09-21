# Run from apps/vxpipe_call_engine:
# ERL_FLAGS='+S 4:4' MIX_ENV=test mix run bench/deepgram_tts_session_latency.exs /tmp/report.json 32 20
# Opt-in local diagnostic. Four schedulers cap this lane at half of the development host.
ExUnit.start(seed: 0, max_cases: 1)

defmodule Vxpipe.CallEngine.DeepgramTTSSessionLatencyBench do
  use ExUnit.Case, async: false

  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech
  alias Vxpipe.Providers.Deepgram.TTSSession, as: FluxSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestTextToSpeechTransport

  @sample_rate 16_000
  @frame_ms 20
  @frame :binary.copy(<<1, 0>>, div(@sample_rate * @frame_ms, 1_000))

  @tag timeout: 120_000
  @tag :capture_log
  test "measure isolated native Deepgram TTS session flow" do
    {report_path, concurrency, rounds} = arguments!()

    trials =
      1..concurrency
      |> Task.async_stream(&worker(&1, rounds),
        max_concurrency: concurrency,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.flat_map(fn
        {:ok, samples} -> samples
        {:exit, reason} -> flunk("native Deepgram TTS worker exited: #{inspect(reason)}")
      end)

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      concurrency: concurrency,
      rounds_per_worker: rounds,
      successful_requests: length(trials),
      fixture:
        "controlled private wire; one 20 ms 16 kHz mono PCM16 frame; provider terminal after exact channel credit",
      metrics: %{
        completion_us: stats(trials, :completion_us),
        settlement_us: stats(trials, :settlement_us)
      },
      trials: trials
    }

    File.mkdir_p!(Path.dirname(report_path))
    File.write!(report_path, JSON.encode!(report))
    IO.puts("Deepgram TTS session report written to #{report_path}; #{length(trials)} requests")
  end

  defp worker(worker, rounds) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {session, wire} = start_session(CapabilityTree.scope(tree))
      Enum.map(1..rounds, &measure(session, wire, worker, &1))
    after
      Supervisor.stop(tree)
    end
  end

  defp start_session(scope) do
    {:ok, config} =
      FluxTextToSpeech.new(
        api_key: "synthetic-load-secret",
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: @sample_rate
      )

    {:ok, session, :starting} =
      Session.start(scope,
        provider: FluxSession,
        options: [
          model: config.model,
          encoding: config.encoding,
          sample_rate: config.sample_rate
        ],
        private: [
          config: config,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: self(), ready_on_start: true]
        ]
      )

    assert_receive {:test_tts_transport_started, wire, _connection}, 5_000
    ready = receive_event(session, :ready)
    :ok = Session.ack(session, ready)
    {session, wire}
  end

  defp measure(session, wire, worker, round) do
    started = now()
    assert {:ok, request} = Session.speak(session, "load")
    assert_receive {:test_tts_control, ^wire, _speak}, 5_000
    assert_receive {:test_tts_control, ^wire, _flush}, 5_000
    submitted = receive_event(session, :input_submitted)
    assert submitted.request_ref == request.ref
    assert :ok = Session.ack(session, submitted)

    wire_reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, @frame)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}, 5_000
    assert audio.request_ref == request.ref
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_tts_audio_result, ^wire_reference, :ok}, 5_000

    speech_id = "dg_sp_#{worker}_#{round}"

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => speech_id})
    )

    completed = receive_event(session, :completed)
    assert completed.request_ref == request.ref
    assert completed.provider_request_id == speech_id
    assert :ok = Session.ack(session, completed)
    completion_us = now() - started
    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, playback} = Session.cancel(session, ticket, @frame_ms)
    assert playback.request_played_ms == @frame_ms

    %{
      worker: worker,
      round: round,
      completion_us: completion_us,
      settlement_us: now() - started
    }
  end

  defp receive_event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 5_000
    event
  end

  defp arguments! do
    report =
      Enum.at(
        System.argv(),
        0,
        Path.join(System.tmp_dir!(), "vxpipe-deepgram-tts-session-latency.json")
      )

    concurrency = integer_argument!(1, 32)
    rounds = integer_argument!(2, 20)

    if concurrency in 1..32 and rounds in 1..100,
      do: {report, concurrency, rounds},
      else: raise(ArgumentError, "concurrency must be 1..32 and rounds must be 1..100")
  end

  defp integer_argument!(index, default) do
    case Enum.at(System.argv(), index) do
      nil -> default
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> raise ArgumentError, "expected an integer at argument #{index + 1}"
  end

  defp stats(samples, key) do
    values = samples |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sort()
    count = length(values)

    %{
      n: count,
      p50: Enum.at(values, ceil(count * 0.50) - 1),
      p95: Enum.at(values, ceil(count * 0.95) - 1),
      p99: Enum.at(values, ceil(count * 0.99) - 1),
      max: List.last(values)
    }
  end

  defp now, do: System.monotonic_time(:microsecond)
end
