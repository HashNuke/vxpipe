# Run from apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/speech_latency.exs /tmp/vxpipe-speech-latency.json
# Isolated process-tree diagnostic; does not create calls or contact providers.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.SpeechLatencyBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.Speech.{Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionProbe

  @report_path List.first(System.argv()) ||
                 Path.join(System.tmp_dir!(), "vxpipe-speech-latency.json")
  @warmup_rounds 10
  @measured_rounds 200
  @repeats 3
  @levels [1, 8, 32]
  @metrics [:audio_admit_us, :speech_start_us, :first_transcript_us, :turn_end_us, :turn_total_us]

  @tag timeout: 120_000
  @tag :capture_log
  test "measure real Morse recognition at increasing concurrency and during another startup" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    trials =
      for repeat <- 1..@repeats,
          level <- @levels,
          path <- if(rem(repeat, 2) == 1, do: [:legacy, :semantic], else: [:semantic, :legacy]),
          held? <- held_scenarios(path, level, repeat) do
        run_trial(tasks, path, level, repeat, held?)
      end

    summaries =
      trials
      |> Enum.group_by(&{&1.path, &1.concurrency, &1.held_start?})
      |> Enum.map(fn {{path, concurrency, held?}, group} ->
        samples = Enum.flat_map(group, & &1.samples)

        %{
          path: path,
          concurrency: concurrency,
          held_start?: held?,
          repeats: length(group),
          successful_turns: length(samples),
          startup_ready_us: stats(Enum.flat_map(group, & &1.startup_ready_us)),
          metrics: metric_summary(samples)
        }
      end)
      |> Enum.sort_by(&{&1.held_start?, &1.concurrency, &1.path})

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      workload: :unpaced_morse_pcm,
      warmup_rounds: @warmup_rounds,
      measured_rounds: @measured_rounds,
      fixture: "E; raw 16kHz mono linear16; dot+3-unit gap, then 11-unit gap",
      summaries: summaries,
      trials:
        Enum.map(trials, fn trial ->
          trial |> Map.delete(:samples) |> Map.put(:metrics, metric_summary(trial.samples))
        end)
    }

    File.write!(@report_path, JSON.encode!(report))
    IO.puts("Speech latency measurements written to #{@report_path}")
    Enum.each(summaries, &print_summary/1)
  end

  defp held_scenarios(:semantic, 32, repeat),
    do: if(rem(repeat, 2) == 1, do: [false, true], else: [true, false])

  defp held_scenarios(_path, _level, _repeat), do: [false]

  defp run_trial(tasks, path, count, repeat, held?) do
    observer = self()
    gate = make_ref()

    rooms =
      if path == :legacy do
        for _ <- 1..count do
          incarnation = "rinc-bench-#{System.unique_integer([:positive, :monotonic])}"
          supervisor = start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation})
          {incarnation, supervisor}
        end
      else
        List.duplicate(nil, count)
      end

    jobs =
      Enum.map(rooms, fn incarnation ->
        Task.Supervisor.async_nolink(tasks, fn -> worker(path, incarnation, observer, gate) end)
      end)

    startup =
      Enum.map(jobs, fn task ->
        pid = task.pid
        assert_receive {:worker_ready, ^pid, microseconds}, 5_000
        microseconds
      end)

    # Prepare clients before holding the shared startup supervisor: this scenario
    # measures already-active recognition rather than repeating startup queueing.
    held = if held?, do: hold_start(tasks)

    samples =
      try do
        rounds =
          for round <- 1..(@warmup_rounds + @measured_rounds) do
            Enum.each(jobs, &send(&1.pid, {:round, gate, round}))

            results =
              Enum.map(jobs, fn task ->
                pid = task.pid
                assert_receive {:turn_result, ^pid, ^round, result}, 5_000
                result
              end)

            if round > @warmup_rounds, do: results, else: []
          end

        List.flatten(rounds)
      after
        release_start(held)
        Enum.each(jobs, &send(&1.pid, {:finish, gate}))
        Enum.each(jobs, &Task.await(&1, 5_000))

        Enum.each(rooms, fn
          nil -> :ok
          {incarnation, _supervisor} -> stop_supervised!({RoomCapabilitySupervisor, incarnation})
        end)
      end

    assert length(samples) == count * @measured_rounds

    %{
      path: path,
      concurrency: count,
      repeat: repeat,
      held_start?: held?,
      startup_ready_us: startup,
      samples: samples
    }
  end

  defp worker(path, incarnation, observer, gate) do
    started = now()
    client = start_client(path, incarnation)
    startup_ready = now() - started
    client = Map.put(client, :pcm, reference_e())
    send(observer, {:worker_ready, self(), startup_ready})

    try do
      rounds(client, observer, gate)
    after
      close_client(client)
    end
  end

  defp rounds(client, observer, gate) do
    receive do
      {:round, ^gate, round} ->
        result = measure_turn(client, round)
        send(observer, {:turn_result, self(), round, result})
        rounds(client, observer, gate)

      {:finish, ^gate} ->
        :ok
    after
      10_000 -> flunk("benchmark coordinator did not release the next round")
    end
  end

  defp start_client(:semantic, _incarnation) do
    {:ok, pid} = Session.start(provider: MorseSession)
    assert_receive {:vxpipe_speech, %Event{session: ^pid, kind: :ready} = ready}, 5_000
    assert :ok = Session.ack(pid, ready)
    %{path: :semantic, pid: pid}
  end

  defp start_client(:legacy, {incarnation, supervisor}) do
    {:ok, config} = MorseCodeSTT.new([])

    identity = [
      tenant_id: "tenant-bench",
      room_id: "room-#{incarnation}",
      incarnation_id: incarnation,
      participant_id: "human",
      connection_id: "conn"
    ]

    {:ok, pid} =
      DynamicSupervisor.start_child(
        supervisor,
        {SpeechToText,
         identity ++
           [
             owner: self(),
             provider: {MorseCodeSTT, config},
             transport: {MorseCodeSTT.Transport, []}
           ]}
      )

    assert_receive {:vxpipe_stt_signal, ^pid, _, %Signal{kind: :connected}}, 5_000
    %{path: :legacy, pid: pid, identity: identity, supervisor: supervisor}
  end

  defp measure_turn(client, round) do
    {prefix, suffix} = client.pcm
    started = now()
    assert :ok = push(client, prefix, round * 2 - 1)
    first_admission = now() - started
    speech_started = receive_kind(client, :started)
    first_text = receive_kind(client, :text)
    tail_started = now()
    assert :ok = push(client, suffix, round * 2)
    final_admission = now() - tail_started
    ended = receive_kind(client, :ended)

    %{
      audio_admit_us: [first_admission, final_admission],
      speech_start_us: speech_started - started,
      first_transcript_us: first_text - started,
      turn_end_us: ended - tail_started,
      turn_total_us: ended - started
    }
  end

  defp push(%{path: :semantic, pid: pid}, pcm, _sequence), do: Session.push_audio(pid, pcm)

  defp push(%{path: :legacy} = client, pcm, sequence) do
    frame =
      struct!(
        AudioFrame,
        client.identity ++
          [
            track_id: "morse",
            codec: :linear16,
            sample_rate: 16_000,
            channels: 1,
            sequence_number: sequence,
            timestamp: sequence * 320,
            payload: pcm,
            received_at: System.monotonic_time(:millisecond)
          ]
      )

    SpeechToText.push_audio(client.pid, frame)
  end

  defp receive_kind(%{path: :semantic, pid: pid}, kind) do
    expected = %{started: :speech_started, text: :transcript, ended: :turn_ended}
    assert_receive {:vxpipe_speech, %Event{session: ^pid} = event}, 5_000
    assert event.kind == Map.fetch!(expected, kind)
    assert :ok = Session.ack(pid, event)
    if kind != :started, do: assert(event.text == "E")
    now()
  end

  defp receive_kind(%{path: :legacy, pid: pid}, kind) do
    expected = %{started: :turn_started, text: :transcript_updated, ended: :turn_ended}
    assert_receive {:vxpipe_stt_signal, ^pid, _, %Signal{} = signal}, 5_000
    assert signal.kind == Map.fetch!(expected, kind)
    if kind != :started, do: assert(signal.text == "E")
    now()
  end

  defp close_client(%{path: :semantic, pid: pid}), do: Session.close(pid)

  defp close_client(%{path: :legacy} = client),
    do:
      DynamicSupervisor.terminate_child(
        client.supervisor,
        client.pid
      )

  defp hold_start(tasks) do
    owner = self()

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: owner,
          private: [observer: owner, hold_start?: true]
        )
      end)

    assert_receive {:probe_initializing, provider, _channel}, 1_000
    %{task: task, provider: provider, monitor: Process.monitor(provider)}
  end

  defp release_start(nil), do: :ok

  defp release_start(held) do
    provider = held.provider
    monitor = held.monitor
    refute_received {:DOWN, ^monitor, :process, ^provider, _reason}
    Process.demonitor(monitor, [:flush])
    send(provider, :release_start)
    assert {:ok, session} = Task.await(held.task, 2_000)
    assert :ok = Session.close(session)
  end

  defp reference_e do
    dot =
      for i <- 0..959, into: <<>> do
        sample = if rem(div(i, 11), 2) == 0, do: 3_000, else: -3_000
        <<sample::signed-little-16>>
      end

    {dot <> :binary.copy(<<0, 0>>, 3 * 960), :binary.copy(<<0, 0>>, 11 * 960)}
  end

  defp metric_summary(samples) do
    Map.new(@metrics, fn metric ->
      values = Enum.flat_map(samples, fn sample -> List.wrap(Map.fetch!(sample, metric)) end)
      {metric, stats(values)}
    end)
  end

  defp stats(values) do
    values = Enum.sort(values)

    %{
      n: length(values),
      p50: percentile(values, 0.50),
      p95: percentile(values, 0.95),
      p99: percentile(values, 0.99),
      max: List.last(values)
    }
  end

  defp percentile(values, fraction),
    do: Enum.at(values, max(ceil(length(values) * fraction) - 1, 0))

  defp now, do: System.monotonic_time(:microsecond)

  defp print_summary(summary) do
    text = summary.metrics.first_transcript_us
    ended = summary.metrics.turn_end_us

    IO.puts(
      "#{summary.path} n=#{summary.concurrency} held=#{summary.held_start?} " <>
        "turns=#{summary.successful_turns} text p95=#{text.p95}us p99=#{text.p99}us " <>
        "end p95=#{ended.p95}us p99=#{ended.p99}us"
    )
  end
end
