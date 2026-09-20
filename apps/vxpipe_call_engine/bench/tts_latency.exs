# Run from apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/tts_latency.exs /tmp/vxpipe-tts-latency.json 4 10
# Opt-in local diagnostic. Concurrency is capped at half of online schedulers.
ExUnit.start(seed: 0, max_cases: 1)

defmodule Vxpipe.CallEngine.TTSLatencyBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  @sample_rate 16_000
  @bytes_per_sample 2
  @settings [sample_rate: @sample_rate, unit_duration_ms: 60, amplitude: 2_048]
  @metrics [:first_audio_us, :generation_completion_us, :sink_playout_completion_us]

  @tag timeout: 120_000
  @tag :capture_log
  test "measure native TTS generation separately from a controlled sink clock" do
    {report_path, concurrency, rounds, capacity} = arguments!()
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    observer = self()
    gate = make_ref()

    jobs =
      Enum.map(1..concurrency, fn worker ->
        Task.Supervisor.async_nolink(tasks, fn -> worker(worker, rounds, observer, gate) end)
      end)

    Enum.each(jobs, fn job ->
      pid = job.pid
      assert_receive {:tts_latency_ready, ^pid}, 5_000
    end)

    Enum.each(jobs, &send(&1.pid, {:run_tts_latency, gate}))
    samples = jobs |> Enum.flat_map(&Task.await(&1, 120_000))

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      concurrency: concurrency,
      concurrency_cap: capacity,
      rounds_per_worker: rounds,
      successful_requests: length(samples),
      fixture:
        "E; native Morse TTS; 16 kHz mono signed little-endian PCM16; 60 ms unit; amplitude 2048",
      sink:
        "controlled monotonic clock scheduled from PCM duration; no audio device, network or acoustic measurement",
      boundaries:
        "first audio is envelope receipt; generation completion is completed-event ACK; sink playout completion waits through the final scheduled PCM duration",
      metrics: Map.new(@metrics, &{&1, stats(samples, &1)}),
      trials: samples
    }

    File.mkdir_p!(Path.dirname(report_path))
    File.write!(report_path, JSON.encode!(report))
    IO.puts("TTS latency report written to #{report_path}; #{length(samples)} requests")
  end

  defp arguments! do
    report_path =
      Enum.at(System.argv(), 0, Path.join(System.tmp_dir!(), "vxpipe-tts-latency.json"))

    concurrency = integer_argument!(1, 1)
    rounds = integer_argument!(2, 10)
    capacity = max(div(System.schedulers_online(), 2), 1)

    if concurrency in 1..capacity and rounds in 1..100 do
      {report_path, concurrency, rounds, capacity}
    else
      raise ArgumentError,
            "concurrency must be 1..#{capacity} and rounds must be 1..100"
    end
  end

  defp integer_argument!(index, default) do
    case Enum.at(System.argv(), index) do
      nil -> default
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> raise ArgumentError, "expected an integer at argument #{index + 1}"
  end

  defp worker(worker, rounds, observer, gate) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {:ok, allocation, :starting} =
        Session.start(CapabilityTree.scope(tree),
          provider: MorseSession,
          options: @settings,
          private: [emit_interval_ms: 0]
        )

      ready = receive_event(allocation, :ready)
      :ok = Session.ack(allocation, ready)
      send(observer, {:tts_latency_ready, self()})
      assert_receive {:run_tts_latency, ^gate}, 5_000

      Enum.map(1..rounds, fn round -> measure(allocation, worker, round) end)
    after
      Supervisor.stop(tree)
    end
  end

  defp measure(allocation, worker, round) do
    started = now()
    assert {:ok, request} = Session.speak(allocation, "E")

    submitted = receive_event(allocation, :input_submitted)
    assert :ok = Session.ack(allocation, submitted)
    assert submitted.request_ref == request.ref

    {first_audio_us, generated_bytes, sink_deadline} =
      drain(allocation, request.ref, started, nil, 0, nil)

    generation_completion_us = now() - started
    wait_until(sink_deadline)
    sink_playout_completion_us = now() - started
    played_ms = div(generated_bytes * 1_000, @sample_rate * @bytes_per_sample)
    assert {:ok, ticket} = Session.fence_output(allocation, request)
    assert {:ok, playback} = Session.cancel(allocation, ticket, played_ms)
    assert playback.request_played_ms == played_ms

    %{
      worker: worker,
      round: round,
      generated_bytes: generated_bytes,
      first_audio_us: first_audio_us,
      generation_completion_us: generation_completion_us,
      sink_playout_completion_us: sink_playout_completion_us
    }
  end

  defp drain(allocation, request_ref, started, first_audio_us, generated_bytes, sink_deadline) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^allocation} = audio} ->
        received = now()
        first_audio_us = first_audio_us || received - started
        assert :ok = Session.validate_audio(allocation, audio)
        assert audio.request_ref == request_ref
        accepted = now()
        duration_us = div(byte_size(audio.payload) * 1_000_000, @sample_rate * @bytes_per_sample)
        sink_deadline = max(sink_deadline || accepted, accepted) + duration_us
        assert :ok = Session.ack_audio(allocation, audio)

        drain(
          allocation,
          request_ref,
          started,
          first_audio_us,
          generated_bytes + byte_size(audio.payload),
          sink_deadline
        )

      {:vxpipe_speech, %Event{session: ^allocation, kind: :completed} = event} ->
        assert :ok = Session.ack(allocation, event)
        assert event.request_ref == request_ref
        {first_audio_us, generated_bytes, sink_deadline}
    after
      5_000 -> flunk("native TTS did not complete")
    end
  end

  defp receive_event(allocation, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event}, 5_000
    event
  end

  defp wait_until(deadline) do
    remaining = max(deadline - now(), 0)

    receive do
    after
      div(remaining + 999, 1_000) -> :ok
    end
  end

  defp stats(samples, metric) do
    values = samples |> Enum.map(&Map.fetch!(&1, metric)) |> Enum.sort()
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
