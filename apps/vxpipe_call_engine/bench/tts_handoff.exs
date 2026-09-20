# From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/tts_handoff.exs /tmp/tts-handoff.json
# Isolated local providers. Sink delay models bounded acceptance, not physical playback.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.TTSHandoffBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: STT
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: TTS
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionOwner

  @report List.first(System.argv()) || "/tmp/tts-handoff.json"
  @rounds 8
  @settings [sample_rate: 8_000, unit_duration_ms: 20]
  @metrics [
    :candidate_setup_us,
    :wrong_direction_us,
    :rejection_us,
    :first_audio_us,
    :generation_end_us,
    :sink_acceptance_end_us,
    :stt_text_us,
    :stt_end_us,
    :close_us
  ]

  @tag timeout: 180_000
  @tag :capture_log
  test "TTS handoff and rejection preserve exact output, STT and local recovery under load" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    actors =
      start_supervised!({DynamicSupervisor, name: __MODULE__.Actors, strategy: :one_for_one})

    trials =
      for repeat <- 1..3, count <- [1, 8, 32], delay <- [0, 2], mode <- [:direct, :adopted] do
        trial(tasks, actors, repeat, count, delay, mode)
      end

    File.write!(
      @report,
      JSON.encode!(%{
        elixir: System.version(),
        otp: System.otp_release(),
        schedulers: System.schedulers_online(),
        rounds: @rounds,
        repeats: 3,
        workload:
          "1/8/32 scopes with STT and sequential fresh TTS allocations; direct/adopted startup; eight rounds; 0/2ms simulated sink acceptance per 20ms PCM chunk; unpaced provider; in seven rounds STT completes while the first TTS audio credit is withheld; round 4 kills Channel then completes STT and explicitly replaces TTS",
        setup_measurement:
          "candidate_setup_us includes full candidate lifecycle setup; adopted mode includes lease creation, adoption, denied stale-lease close and lease teardown before consuming readiness",
        assertions:
          "exact independent E PCM/text/end and request correlation, expected control kinds, nonfatal wrong-direction and text rejection, old lease denied, exact stale audio rejected after fault, provider/channel/tree teardown and no remaining dynamic children",
        timing_boundaries:
          "rejection_us includes failed-event ACK after engine admission; sink_acceptance_end_us includes successful final audio-credit ACK; fault safe/teardown measurements are observed upper bounds after sibling STT completes; fixed direct-then-adopted order with no warmup",
        limits:
          "bounded smoke/load evidence, not comparative tail estimates; selective receives are not independent control/audio ordering proof; local Morse only; no physical playback, hosted/network behavior, room integration, cancellation or production capacity claim; prior STT-only reports are separate workloads",
        trials: trials
      })
    )

    IO.puts("TTS handoff report written to #{@report}; #{length(trials)} trials")
  end

  defp trial(tasks, actors, repeat, count, delay, mode) do
    observer = self()

    scopes =
      for _ <- 1..count do
        id = make_ref()
        tree = start_supervised!(Supervisor.child_spec({CapabilityTree, owner: observer}, id: id))
        {id, CapabilityTree.scope(tree)}
      end

    gate = make_ref()

    jobs =
      Enum.map(scopes, fn {_id, scope} ->
        Task.Supervisor.async_nolink(tasks, fn ->
          stt = start_stt(scope)
          send(observer, {:waiting, self()})
          assert_receive {:go, ^gate}, 5_000
          samples = for round <- 1..@rounds, do: round(scope, actors, stt, delay, mode, round)
          close(stt)
          samples
        end)
      end)

    Enum.each(jobs, fn job ->
      pid = job.pid
      assert_receive {:waiting, ^pid}, 5_000
    end)

    before_memory = :erlang.memory(:total)
    Enum.each(jobs, &send(&1.pid, {:go, gate}))
    samples = Enum.flat_map(jobs, &Task.await(&1, 30_000))

    Enum.each(scopes, fn {id, scope} ->
      assert %{active: 0} = DynamicSupervisor.count_children(scope.sessions)
      stop_supervised!(id)
    end)

    assert %{active: 0} = DynamicSupervisor.count_children(actors)
    faults = Enum.flat_map(samples, & &1.faults)
    assert length(faults) == count

    IO.puts(
      "TTS repeat=#{repeat} scopes=#{count} delay=#{delay} mode=#{mode}: #{length(samples)} turns"
    )

    %{
      repeat: repeat,
      scopes: count,
      sink_delay_ms: delay,
      mode: mode,
      tts_turns: length(samples),
      stt_turns: length(samples),
      fault_trials: length(faults),
      metrics:
        Map.new(@metrics, fn key -> {key, stats(Enum.map(samples, &Map.fetch!(&1, key)))} end),
      faults: faults,
      memory_before_bytes: before_memory,
      memory_after_bytes: :erlang.memory(:total),
      process_count_after: :erlang.system_info(:process_count)
    }
  end

  defp round(scope, actors, stt, delay, mode, round) do
    {prefix, suffix, expected} = fixture()
    started = now()
    assert :ok = Session.push_audio(stt, prefix)
    event(stt, :speech_started)
    text = event(stt, :transcript)
    assert text.text == "E"
    stt_text_us = now() - started

    {tts, ready_us} = candidate(scope, actors, mode)

    {tts, ready_us, faults} =
      if round == 4 do
        fault = fault(tts, stt, suffix, text.turn_ref)
        {replacement, ready_us} = candidate(scope, actors, mode)
        fault = Map.put(fault, :replacement_ready_us, now() - fault.started_us)
        {replacement, ready_us, [Map.delete(fault, :started_us)]}
      else
        {tts, ready_us, []}
      end

    started = now()
    assert {:error, :unsupported_operation} = Session.push_audio(tts, <<0, 0>>)
    wrong_direction_us = now() - started
    started = now()
    assert {:ok, rejected} = Session.speak(tts, "☃")
    failed = event(tts, :failed)
    assert failed.request_ref == rejected.ref
    assert failed.reason == :unsupported_character
    rejection_us = now() - started
    started = now()
    assert {:ok, %{ref: request}} = Session.speak(tts, "E")
    submitted = event(tts, :input_submitted)
    assert submitted.request_ref == request

    stt_end_us =
      case faults do
        [fault] -> fault.stt_end_us
        [] -> nil
      end

    finish_stt = fn -> finish_stt(stt, suffix, text.turn_ref) end

    timing = %{first: nil, sink_end: nil, stt_end: stt_end_us}
    {pcm, timing} = drain(tts, request, started, delay, [], timing, finish_stt)
    generation_end_us = now() - started
    assert pcm == expected

    started = now()
    close(tts)

    %{
      candidate_setup_us: ready_us,
      wrong_direction_us: wrong_direction_us,
      rejection_us: rejection_us,
      first_audio_us: timing.first,
      generation_end_us: generation_end_us,
      sink_acceptance_end_us: timing.sink_end,
      stt_text_us: stt_text_us,
      stt_end_us: timing.stt_end,
      close_us: now() - started,
      faults: faults
    }
  end

  defp candidate(scope, actors, mode) do
    started = now()
    consumer = self()
    options = [provider: TTS, options: @settings, private: [emit_interval_ms: 0]]

    allocation =
      case mode do
        :direct ->
          {:ok, allocation, :starting} = Session.start(scope, options)
          allocation

        :adopted ->
          {:ok, lease} = DynamicSupervisor.start_child(actors, {SpeechSessionOwner, consumer})
          monitor = Process.monitor(lease)

          {:ok, allocation, :starting} =
            Session.start(scope, options ++ [consumer: nil, lease: lease])

          assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _}}, 5_000
          original_tree = Session.tree(allocation)

          assert :ok =
                   SpeechSessionOwner.run(lease, fn _ -> Session.adopt(allocation, consumer) end)

          assert Session.tree(allocation) == original_tree

          assert {:error, :not_owner} =
                   SpeechSessionOwner.run(lease, fn _ -> Session.close(allocation) end)

          :ok = DynamicSupervisor.terminate_child(actors, lease)
          assert_receive {:DOWN, ^monitor, :process, ^lease, _}, 5_000
          allocation
      end

    event(allocation, :ready)
    {allocation, now() - started}
  end

  defp start_stt(scope) do
    {:ok, allocation, :starting} = Session.start(scope, provider: STT, options: @settings)
    event(allocation, :ready)
    allocation
  end

  defp fault(tts, stt, suffix, turn_ref) do
    assert {:ok, %{ref: request}} = Session.speak(tts, "E")
    submitted = event(tts, :input_submitted)
    assert submitted.request_ref == request
    assert_receive {:vxpipe_speech_audio, %{session: ^tts} = audio}, 5_000
    assert audio.request_ref == request
    descendants = monitor_allocation(tts)
    channel = GenServer.whereis(Channel.address(tts))
    started = now()
    Process.exit(channel, :kill)
    stt_end_us = finish_stt(stt, suffix, turn_ref)
    assert_receive {:vxpipe_speech_closed, ^tts, _}, 5_000
    safe_us = now() - started
    assert {:error, :closed} = Session.validate_audio(tts, audio)
    assert_terminated(descendants)
    refute_received {:vxpipe_speech, %Event{session: ^tts, kind: :completed}}

    %{
      started_us: started,
      safe_observed_us: safe_us,
      teardown_us: now() - started,
      stt_end_us: stt_end_us
    }
  end

  defp finish_stt(stt, suffix, turn_ref) do
    started = now()
    assert :ok = Session.push_audio(stt, suffix)
    ended = event(stt, :turn_ended)
    assert ended.turn_ref == turn_ref
    assert ended.text == "E"
    now() - started
  end

  defp drain(allocation, request, started, delay, chunks, timing, finish_stt) do
    receive do
      {:vxpipe_speech_audio, %{session: ^allocation} = audio} ->
        assert audio.request_ref == request
        assert byte_size(audio.payload) == 320
        timing = %{timing | first: timing.first || now() - started}
        assert :ok = Session.validate_audio(allocation, audio)
        timing = %{timing | stt_end: timing.stt_end || finish_stt.()}
        assert :ok = Session.validate_audio(allocation, audio)
        accept_sink(delay)
        assert :ok = Session.ack_audio(allocation, audio)

        drain(
          allocation,
          request,
          started,
          delay,
          [audio.payload | chunks],
          %{timing | sink_end: now() - started},
          finish_stt
        )

      {:vxpipe_speech, %Event{session: ^allocation, kind: :completed} = completed} ->
        assert completed.request_ref == request
        assert :ok = Session.ack(allocation, completed)
        assert length(chunks) == 15
        {chunks |> Enum.reverse() |> IO.iodata_to_binary(), timing}

      {:vxpipe_speech, %Event{session: ^allocation}} ->
        flunk("unexpected or duplicate TTS control event")
    after
      5_000 -> flunk("TTS output stalled")
    end
  end

  defp accept_sink(0), do: :ok

  defp accept_sink(delay) do
    tick = make_ref()
    Process.send_after(self(), tick, delay)
    assert_receive ^tick, 5_000
  end

  defp event(allocation, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation} = event}, 5_000
    assert event.kind == kind
    assert event.generation == allocation.generation
    assert :ok = Session.ack(allocation, event)
    event
  end

  defp close(allocation) do
    descendants = monitor_allocation(allocation)
    assert :ok = Session.close(allocation)
    assert_terminated(descendants)
  end

  defp monitor_allocation(allocation) do
    pids = [
      Session.tree(allocation),
      Session.provider(allocation),
      GenServer.whereis(Channel.address(allocation))
    ]

    Enum.map(pids, &{&1, Process.monitor(&1)})
  end

  defp assert_terminated(monitors) do
    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    end
  end

  defp fixture do
    dot =
      for index <- 0..159, into: <<>> do
        sample = round(:math.sin(2.0 * :math.pi() * 700 / 8_000 * index) * 4_096)
        <<sample::signed-little-16>>
      end

    prefix = dot <> :binary.copy(<<0, 0>>, 480)
    suffix = :binary.copy(<<0, 0>>, 1_760)
    {prefix, suffix, prefix <> suffix}
  end

  defp stats(values) do
    sorted = Enum.sort(values)

    %{
      n: length(values),
      p50: percentile(sorted, 0.5),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      max: List.last(sorted)
    }
  end

  defp percentile(sorted, fraction),
    do: Enum.at(sorted, max(ceil(length(sorted) * fraction) - 1, 0))

  defp now, do: System.monotonic_time(:microsecond)
end
