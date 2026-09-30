# Run from apps/vxpipe_call_engine:
# ERL_FLAGS='+S 4:4' MIX_ENV=test mix run bench/google_speech_session_latency.exs /tmp/report.json 16 20
# Opt-in local diagnostic. Four schedulers and at most 16 sessions per lane bound the host load.
ExUnit.start(seed: 0, max_cases: 1)

defmodule Vxpipe.CallEngine.GoogleSpeechSessionLatencyBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.{TestGoogleSTTTransport, TestRequestTTS}
  alias Vxpipe.Providers.Google.{STT, STTSession, TTS, TTSSession}

  @frame :binary.copy(<<1, 0>>, 320)

  @tag timeout: 120_000
  @tag :capture_log
  test "measure scoped Google speech delivery with private synthetic transports" do
    {report_path, concurrency, rounds} = arguments!()

    tts = trials(concurrency, rounds, &tts_worker/2)
    stt = trials(concurrency, rounds, &stt_worker/2)

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      concurrency: concurrency,
      rounds_per_worker: rounds,
      fixture: "private synthetic request and socket; one 20 ms mono PCM16 frame per turn",
      tts: %{
        completed: length(tts),
        completion_us: stats(tts, :completion_us),
        settlement_us: stats(tts, :settlement_us)
      },
      stt: %{
        completed: length(stt),
        admission_us: stats(stt, :admission_us),
        turn_end_us: stats(stt, :turn_end_us)
      }
    }

    File.mkdir_p!(Path.dirname(report_path))
    File.write!(report_path, JSON.encode!(report))

    IO.puts(
      "Google speech session report written to #{report_path}; #{length(tts)} TTS and #{length(stt)} STT turns"
    )
  end

  defp trials(concurrency, rounds, worker) do
    1..concurrency
    |> Task.async_stream(&worker.(&1, rounds),
      max_concurrency: concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.flat_map(fn
      {:ok, samples} -> samples
      {:exit, reason} -> flunk("Google speech load worker exited: #{inspect(reason)}")
    end)
  end

  defp tts_worker(worker, rounds) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {:ok, config} = TTS.new(api_key: "synthetic-key")
      config = %{config | endpoint: self()}

      {:ok, session, :starting} =
        Session.start(CapabilityTree.scope(tree),
          provider: TTSSession,
          options: [model: config.model, voice: config.voice],
          private: [config: config, request_module: TestRequestTTS]
        )

      ack_event(session, :ready)
      Enum.map(1..rounds, &tts_turn(session, worker, &1))
    after
      Supervisor.stop(tree)
    end
  end

  defp tts_turn(session, worker, round) do
    started = now()
    assert {:ok, request} = Session.speak(session, "load")
    submitted = ack_event(session, :input_submitted)
    assert submitted.request_ref == request.ref
    assert_receive {:test_request_tts_started, task, "load"}, 5_000
    send(task, {:audio, @frame})
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}, 5_000
    assert audio.request_ref == request.ref
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_request_tts_audio_consumed, ^task, :ok}, 5_000
    send(task, :complete)
    completed = ack_event(session, :completed)
    assert completed.request_ref == request.ref
    completion = now() - started
    assert :ok = Session.settle_output(session, request, 20)
    %{worker: worker, round: round, completion_us: completion, settlement_us: now() - started}
  end

  defp stt_worker(worker, rounds) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {:ok, config} = STT.new(api_key: "synthetic-key")

      {:ok, session, :starting} =
        Session.start(CapabilityTree.scope(tree),
          provider: STTSession,
          options: [
            model: config.model,
            encoding: config.encoding,
            sample_rate: config.sample_rate
          ],
          private: [
            config: config,
            wire_module: TestGoogleSTTTransport,
            wire_options: [observer: self()]
          ]
        )

      assert_receive {:test_google_stt_started, wire, _connection}, 5_000
      assert_receive {:test_google_stt_control, ^wire, _setup}, 5_000
      TestGoogleSTTTransport.deliver(wire, ~s({"setupComplete":{}}))
      ack_event(session, :ready)
      Enum.map(1..rounds, &stt_turn(session, wire, worker, &1))
    after
      Supervisor.stop(tree)
    end
  end

  defp stt_turn(session, wire, worker, round) do
    started = now()
    assert :ok = Session.push_audio(session, @frame)
    assert_receive {:test_google_stt_audio, ^wire, @frame}, 5_000
    admission = now() - started
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_START"}}))
    started_event = ack_event(session, :speech_started)
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_END"}}))

    TestGoogleSTTTransport.deliver(
      wire,
      ~s({"serverContent":{"inputTranscription":{"text":"load"}}})
    )

    ended = ack_event(session, :turn_ended)
    assert ended.turn_ref == started_event.turn_ref
    %{worker: worker, round: round, admission_us: admission, turn_end_us: now() - started}
  end

  defp ack_event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 5_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp arguments! do
    report =
      Enum.at(
        System.argv(),
        0,
        Path.join(System.tmp_dir!(), "vxpipe-google-speech-session-latency.json")
      )

    concurrency = integer_argument!(1, 16)
    rounds = integer_argument!(2, 20)

    if concurrency in 1..16 and rounds in 1..100,
      do: {report, concurrency, rounds},
      else: raise(ArgumentError, "concurrency must be 1..16 and rounds must be 1..100")
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
