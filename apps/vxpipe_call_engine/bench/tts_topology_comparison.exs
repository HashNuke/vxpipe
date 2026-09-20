# From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/tts_topology_comparison.exs /tmp/tts-topology-comparison.json
# Isolated topology comparison. It does not load production rooms or hosted providers.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.TTSTopologyComparisonBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{
    SpeechSessionOwner,
    SpeechTopologyPrototype,
    SpeechTopologySTT,
    SpeechTopologyUsage
  }

  @report List.first(System.argv()) || "/tmp/tts-topology-comparison.json"
  @counts System.get_env("TOPOLOGY_COUNTS", "1,8,32,64,128,256")
          |> String.split(",")
          |> Enum.map(&String.to_integer/1)
  @repeats System.get_env("TOPOLOGY_REPEATS", "3") |> String.to_integer()
  @rounds System.get_env("TOPOLOGY_ROUNDS", "8") |> String.to_integer()
  @budgets %{
    first_audio_us: 10_000,
    stt_text_us: 10_000,
    stt_end_us: 10_000,
    cancel_return_us: 10_000,
    replacement_first_audio_us: 10_000,
    replacement_end_us: 100_000,
    cycle_us: 150_000
  }
  @metrics Map.keys(@budgets)

  @tag timeout: 300_000
  @tag :capture_log
  test "merged owner does not cross fixed degradation gates before split owner" do
    start_supervised!({Registry, keys: :unique, name: SpeechTopologyPrototype.registry()})

    sessions =
      start_supervised!(
        {DynamicSupervisor, name: SpeechTopologyPrototype.sessions(), strategy: :one_for_one}
      )

    tasks =
      start_supervised!({Task.Supervisor, name: __MODULE__.Tasks, max_children: :infinity})

    trials =
      for repeat <- 1..@repeats,
          count <- @counts,
          topology <- topology_order(repeat) do
        trial(tasks, sessions, repeat, count, topology)
      end

    summaries =
      for topology <- [:split, :merged], count <- @counts do
        summarize(trials, topology, count)
      end

    split_knee = first_gate_miss(summaries, :split)
    merged_knee = first_gate_miss(summaries, :merged)
    maximum = List.last(@counts)
    pointwise_violations = pointwise_violations(summaries)
    split_32 = summary!(summaries, :split, 32)
    merged_32 = summary!(summaries, :merged, 32)

    comparison_32 = compare(split_32, merged_32)
    phase_summaries_32 = phase_summaries(trials, 32)

    phase_comparisons_32 = %{
      first:
        compare(
          phase_summary!(phase_summaries_32, :split, :first),
          phase_summary!(phase_summaries_32, :merged, :first)
        ),
      steady:
        compare(
          phase_summary!(phase_summaries_32, :split, :steady),
          phase_summary!(phase_summaries_32, :merged, :steady)
        )
    }

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      counts: @counts,
      repeats: @repeats,
      rounds_per_scope: @rounds,
      budgets_us: @budgets,
      workload:
        "paired isolated split-output and merged-owner topologies; each session completes configuration and exact consumer readiness acknowledgement before the simultaneous per-count burst; each cycle admits E through an authorized consumer, acknowledges input_submitted, retains a provider request fact, holds Input after provider acceptance, receives one uncredited native Morse PCM chunk, decodes independent Morse PCM through the real decoder to speech/text/end, fences with an absolute deadline, queues cancel, releases Input, settles exactly one cancelled terminal, then incrementally drains and credits exact native Morse T replacement PCM through completion",
      topology_difference:
        "split models the pre-merge native runtime with Channel plus Output and direct Output credit; merged models the Channel-owned production topology and credits Channel; both use the same test adapter around the production Morse encoder/decoder, authorized consumer, Input, usage sink and synchronization",
      degradation_definition:
        "aggregate p99 is checked against fixed budgets at every tested concurrency; whenever split passes every budget merged must also pass every budget; the first miss is reported as a nonmonotonic diagnostic rather than a capacity knee; any protocol/content/authority error fails immediately; 32-call p99 deltas and a 1ms diagnostic are reported but are not a reliability gate",
      assertions:
        "exact ready/submitted/cancelled/submitted/completed event sequence with acknowledgements; exact request/audio/provider correlation; queued cancel without retry; exact incremental E/T PCM; real Morse speech/text/end while TTS Input is held; retained input usage facts; no unexpected terminal/audio after synchronization; empty session supervisor after every trial",
      limits:
        "isolated native-style process-topology evidence, not the actual native Session/provider implementation or production/hosted-provider capacity; no generation adoption, room policy, physical playback, codec or network; production Morse encoding/decoding runs through a test-only owner/channel/provider adapter; fixed budgets compare this workload on this machine and are not service SLOs",
      split_degradation_count: encode_knee(split_knee),
      merged_degradation_count: encode_knee(merged_knee),
      pointwise_violations: pointwise_violations,
      comparison_at_32: comparison_32,
      phase_comparisons_at_32: phase_comparisons_32,
      phase_summaries_at_32: phase_summaries_32,
      summaries: summaries,
      trials: Enum.map(trials, &Map.delete(&1, :raw_samples))
    }

    File.write!(@report, JSON.encode!(report))

    IO.puts(
      "Topology report written to #{@report}; split knee=#{inspect(split_knee)} merged knee=#{inspect(merged_knee)}"
    )

    assert knee_rank(merged_knee, maximum) >= knee_rank(split_knee, maximum)
    assert pointwise_violations == []
  end

  defp trial(tasks, sessions, repeat, count, topology) do
    observer = self()
    gate = make_ref()
    processes_before = :erlang.system_info(:process_count)
    memory_before = :erlang.memory(:processes_used)
    sampler = start_sampler()

    jobs =
      for _ <- 1..count do
        Task.Supervisor.async_nolink(tasks, fn ->
          {:ok, usage} = SpeechTopologyUsage.start_link(nil)
          {:ok, owner} = SpeechSessionOwner.start_link(self())
          session = SpeechTopologyPrototype.start!(topology, owner, usage, self())
          {:ok, stt} = SpeechTopologySTT.start_link(self())
          :ok = run(owner, fn -> SpeechTopologyPrototype.prepare(session) end)
          event(owner, session, nil, :ready)
          fixtures = %{e: SpeechTopologyPrototype.pcm("E"), t: SpeechTopologyPrototype.pcm("T")}
          send(observer, {:topology_waiting, self(), gate})

          receive do
            {:topology_go, ^gate} -> :ok
          after
            5_000 -> exit(:start_barrier_timeout)
          end

          samples =
            for round <- 1..@rounds do
              session |> cycle(stt, owner, fixtures) |> Map.put(:round, round)
            end

          :ok = SpeechTopologyPrototype.close(session)
          :ok = GenServer.stop(stt, :normal, 5_000)
          :ok = GenServer.stop(usage, :normal, 5_000)
          :ok = GenServer.stop(owner, :normal, 5_000)
          samples
        end)
      end

    waiting =
      Enum.reduce(jobs, MapSet.new(Enum.map(jobs, & &1.pid)), fn _job, pending ->
        assert_receive {:topology_waiting, pid, ^gate}, 5_000
        assert MapSet.member?(pending, pid)
        MapSet.delete(pending, pid)
      end)

    assert MapSet.size(waiting) == 0

    Enum.each(jobs, &send(&1.pid, {:topology_go, gate}))
    samples = Enum.flat_map(jobs, &Task.await(&1, 120_000))
    sampled = stop_sampler(sampler)
    _ = :sys.get_state(sessions)
    assert %{active: 0} = DynamicSupervisor.count_children(sessions)

    IO.puts("topology=#{topology} repeat=#{repeat} scopes=#{count} cycles=#{length(samples)}")

    %{
      topology: topology,
      repeat: repeat,
      scopes: count,
      cycles: length(samples),
      metrics:
        Map.new(@metrics, fn metric ->
          {metric, stats(Enum.map(samples, &Map.fetch!(&1, metric)))}
        end),
      raw_samples: samples,
      process_count_before: processes_before,
      process_count_after: :erlang.system_info(:process_count),
      process_count_peak: sampled.process_count_peak,
      process_memory_before_bytes: memory_before,
      process_memory_after_bytes: :erlang.memory(:processes_used),
      process_memory_peak_bytes: sampled.process_memory_peak,
      run_queue_peak: sampled.run_queue_peak
    }
  end

  defp cycle(session, stt, owner, fixtures) do
    cycle_started = now()
    started = now()

    assert {:ok, request} =
             run(owner, fn ->
               SpeechTopologyPrototype.speak(session, "E", hold_result?: true)
             end)

    admission_us = now() - started
    submitted = event(owner, session, request, :input_submitted)
    assert is_binary(submitted.provider_request_id)
    usage(session, request, submitted.provider_request_id)
    audio = audio(owner, request)
    assert audio.payload == binary_part(fixtures.e, 0, 320)
    assert :ok = run(owner, fn -> SpeechTopologyPrototype.validate_audio(session, audio) end)
    first_audio_us = now() - started
    assert_receive {:speech_owner, ^owner, {:topology_input_held, input, hold}}, 5_000

    turn = make_ref()
    started = now()
    assert :ok = SpeechTopologyPrototype.stt_turn(stt, turn, fixtures.e)
    assert_receive {:topology_speech_started, ^turn}, 5_000
    assert_receive {:topology_text, ^turn, "E"}, 5_000
    stt_text_us = now() - started
    assert_receive {:topology_turn_end, ^turn, "E"}, 5_000
    stt_end_us = now() - started

    assert {:ok, ticket} = run(owner, fn -> SpeechTopologyPrototype.fence(session, request) end)

    cancel =
      Task.async(fn ->
        cancel_started = now()
        result = run(owner, fn -> SpeechTopologyPrototype.cancel(session, ticket, 0) end)
        {now() - cancel_started, result}
      end)

    assert_receive {:topology_cancel_queued, ^request}, 5_000
    SpeechTopologyPrototype.release(input, hold)

    assert {cancel_return_us, {:ok, %{request_ref: ^request, played_ms: 0}}} =
             Task.await(cancel, 5_000)

    event(owner, session, request, :cancelled)

    started = now()

    assert {:ok, replacement} =
             run(owner, fn -> SpeechTopologyPrototype.speak(session, "T") end)

    replacement_submitted = event(owner, session, replacement, :input_submitted)
    usage(session, replacement, replacement_submitted.provider_request_id)
    replacement_audio = audio(owner, replacement)
    expected_first = binary_part(fixtures.t, 0, byte_size(replacement_audio.payload))
    assert replacement_audio.payload == expected_first
    replacement_first_audio_us = now() - started

    replacement_pcm =
      drain_audio(
        owner,
        session,
        replacement,
        byte_size(fixtures.t) - byte_size(replacement_audio.payload),
        [replacement_audio.payload],
        replacement_audio
      )

    assert replacement_pcm == fixtures.t
    event(owner, session, replacement, :completed)
    replacement_end_us = now() - started

    assert {:ok, replacement_ticket} =
             run(owner, fn -> SpeechTopologyPrototype.fence(session, replacement) end)

    assert {:ok, %{request_ref: ^replacement, played_ms: 0}} =
             run(owner, fn ->
               SpeechTopologyPrototype.cancel(session, replacement_ticket, 0)
             end)

    assert :ok = run(owner, fn -> SpeechTopologyPrototype.sync(session) end)
    _ = :sys.get_state(session.provider)
    _ = :sys.get_state(owner)
    refute_received {:speech_owner, ^owner, {:topology_event, _unexpected}}
    refute_received {:speech_owner, ^owner, {:topology_audio, _unexpected}}

    assert admission_us <= 250_000

    %{
      first_audio_us: first_audio_us,
      stt_text_us: stt_text_us,
      stt_end_us: stt_end_us,
      cancel_return_us: cancel_return_us,
      replacement_first_audio_us: replacement_first_audio_us,
      replacement_end_us: replacement_end_us,
      cycle_us: now() - cycle_started
    }
  end

  defp event(owner, session, request, kind) do
    assert_receive {:speech_owner, ^owner, {:topology_event, event}}, 5_000
    assert event.request_ref == request
    assert event.kind == kind
    assert :ok = run(owner, fn -> SpeechTopologyPrototype.ack_event(session, event) end)
    event
  end

  defp audio(owner, request) do
    assert_receive {:speech_owner, ^owner, {:topology_audio, audio}}, 5_000
    assert audio.request_ref == request
    audio
  end

  defp drain_audio(owner, session, _request, 0, chunks, last_audio) do
    assert :ok =
             run(owner, fn -> SpeechTopologyPrototype.validate_audio(session, last_audio) end)

    assert :ok =
             run(owner, fn -> SpeechTopologyPrototype.ack_audio(session, last_audio) end)

    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp drain_audio(owner, session, request, remaining, chunks, last_audio) do
    assert :ok =
             run(owner, fn -> SpeechTopologyPrototype.validate_audio(session, last_audio) end)

    assert :ok =
             run(owner, fn -> SpeechTopologyPrototype.ack_audio(session, last_audio) end)

    next = audio(owner, request)
    assert byte_size(next.payload) <= remaining

    drain_audio(
      owner,
      session,
      request,
      remaining - byte_size(next.payload),
      [next.payload | chunks],
      next
    )
  end

  defp usage(session, request, provider_request_id) do
    assert {:ok,
            %{
              request_ref: ^request,
              input_characters: 1,
              provider_request_id: ^provider_request_id,
              provenance: :locally_measured
            }} = SpeechTopologyPrototype.take_usage(session_usage(session), request)

    assert is_binary(provider_request_id)
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)

  defp session_usage(session) do
    session.usage
  end

  defp summarize(trials, topology, count) do
    selected =
      Enum.filter(trials, &(&1.topology == topology and &1.scopes == count))

    %{
      topology: topology,
      scopes: count,
      cycles: Enum.sum(Enum.map(selected, & &1.cycles)),
      metrics:
        Map.new(@metrics, fn metric ->
          values =
            Enum.flat_map(selected, fn trial ->
              Enum.map(trial.raw_samples, &Map.fetch!(&1, metric))
            end)

          {metric, stats(values)}
        end),
      process_count_peak: Enum.max(Enum.map(selected, & &1.process_count_peak)),
      process_memory_peak_bytes: Enum.max(Enum.map(selected, & &1.process_memory_peak_bytes)),
      run_queue_peak: Enum.max(Enum.map(selected, & &1.run_queue_peak))
    }
  end

  defp first_gate_miss(summaries, topology) do
    Enum.find_value(@counts, :beyond_tested_maximum, fn count ->
      summary = summary!(summaries, topology, count)

      if Enum.any?(@budgets, fn {metric, budget} ->
           summary.metrics[metric].p99 > budget
         end),
         do: count
    end)
  end

  defp pointwise_violations(summaries) do
    Enum.flat_map(@counts, fn count ->
      split = summary!(summaries, :split, count)
      merged = summary!(summaries, :merged, count)
      split_misses = gate_misses(split)
      merged_misses = gate_misses(merged)

      if split_misses == [] and merged_misses != [] do
        [%{scopes: count, split_misses: split_misses, merged_misses: merged_misses}]
      else
        []
      end
    end)
  end

  defp gate_misses(summary) do
    for {metric, budget} <- @budgets,
        summary.metrics[metric].p99 > budget,
        do: metric
  end

  defp summary!(summaries, topology, count),
    do: Enum.find(summaries, &(&1.topology == topology and &1.scopes == count))

  defp phase_summaries(trials, count) do
    for topology <- [:split, :merged], phase <- [:first, :steady] do
      samples =
        trials
        |> Enum.filter(&(&1.topology == topology and &1.scopes == count))
        |> Enum.flat_map(& &1.raw_samples)
        |> Enum.filter(fn sample ->
          if phase == :first, do: sample.round == 1, else: sample.round > 1
        end)

      %{
        topology: topology,
        phase: phase,
        cycles: length(samples),
        metrics:
          Map.new(@metrics, fn metric ->
            {metric, stats(Enum.map(samples, &Map.fetch!(&1, metric)))}
          end)
      }
    end
  end

  defp phase_summary!(summaries, topology, phase),
    do: Enum.find(summaries, &(&1.topology == topology and &1.phase == phase))

  defp compare(split, merged) do
    Map.new(@metrics, fn metric ->
      split_p99 = split.metrics[metric].p99
      merged_p99 = merged.metrics[metric].p99

      {metric,
       %{
         split_p99_us: split_p99,
         merged_p99_us: merged_p99,
         delta_us: merged_p99 - split_p99,
         within_1ms?: merged_p99 <= split_p99 + 1_000
       }}
    end)
  end

  defp knee_rank(:beyond_tested_maximum, maximum), do: maximum + 1
  defp knee_rank(count, _maximum), do: count
  defp encode_knee(:beyond_tested_maximum), do: "beyond_tested_maximum"
  defp encode_knee(count), do: count

  defp topology_order(repeat) when rem(repeat, 2) == 1, do: [:split, :merged]
  defp topology_order(_repeat), do: [:merged, :split]

  defp stats(values) do
    sorted = Enum.sort(values)

    %{
      n: length(values),
      p50: percentile(sorted, 0.50),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      max: List.last(sorted)
    }
  end

  defp percentile(sorted, fraction),
    do: Enum.at(sorted, max(ceil(length(sorted) * fraction) - 1, 0))

  defp start_sampler do
    owner = self()

    spawn_link(fn ->
      sample_loop(owner, %{
        process_count_peak: :erlang.system_info(:process_count),
        process_memory_peak: :erlang.memory(:processes_used),
        run_queue_peak: :erlang.statistics(:run_queue)
      })
    end)
  end

  defp sample_loop(owner, peaks) do
    receive do
      {:stop_sampler, ^owner, reference} ->
        send(owner, {:sampler_stopped, reference, peaks})
    after
      1 ->
        sample_loop(owner, %{
          process_count_peak: max(peaks.process_count_peak, :erlang.system_info(:process_count)),
          process_memory_peak: max(peaks.process_memory_peak, :erlang.memory(:processes_used)),
          run_queue_peak: max(peaks.run_queue_peak, :erlang.statistics(:run_queue))
        })
    end
  end

  defp stop_sampler(sampler) do
    reference = make_ref()
    send(sampler, {:stop_sampler, self(), reference})

    receive do
      {:sampler_stopped, ^reference, peaks} -> peaks
    after
      5_000 -> exit(:sampler_stop_timeout)
    end
  end

  defp now, do: System.monotonic_time(:microsecond)
end
