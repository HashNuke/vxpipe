# From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/tts_cancellation.exs /tmp/tts-cancellation.json
# Local report/accounting and credit boundaries; no physical playback claim.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.TTSCancellationBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: STT
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: TTS
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}

  @report List.first(System.argv()) || "/tmp/tts-cancellation.json"
  @rounds 24
  @settings [sample_rate: 8_000, unit_duration_ms: 20]
  @metrics [
    :first_audio_us,
    :fence_us,
    :cancel_return_us,
    :cancel_terminal_us,
    :replacement_first_audio_us,
    :replacement_generation_end_us,
    :replacement_sink_acceptance_end_us,
    :stt_text_us,
    :stt_end_us
  ]

  @tag timeout: 180_000
  @tag :capture_log
  test "repeated cancellation preserves replacement PCM, reported playback and sibling STT" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    trials =
      for repeat <- 1..3, count <- [1, 8, 32], credit <- [:pending, :credited] do
        trial(tasks, repeat, count, credit)
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
          "1/8/32 scopes, each with persistent native Morse STT and TTS; 24 cancellation/replacement cycles on the same TTS allocation; first chunk pending or credited with second withheld; caller reports 10ms; STT ends while TTS credit is withheld; replacement T drains fully then cancels with zero reported playback",
        assertions:
          "independent E recognition and T PCM, exact request identity, stale credit/timer rejection, duplicate fence/cancel stability, bounded last-result eviction, exact cumulative caller-reported playback, provider/channel/tree teardown, empty scope supervisors",
        timing_boundaries:
          "cancel_terminal_us is observed after cancel returns; generation end includes completed event acknowledgement; sink acceptance end includes last credit ACK; stale credit/timer checks occur after replacement submission; fixed pending-then-credited order, no warmup",
        limits:
          "bounded correctness/load diagnostic, not a capacity limit or comparative performance result; supplied playback numbers are accounting evidence, not an actual sink clock; no physical playback, room integration, hosted providers or network; already-delivered envelopes cannot be recalled by a fence",
        trials: trials
      })
    )

    IO.puts("TTS cancellation report written to #{@report}; #{length(trials)} trials")
  end

  defp trial(tasks, repeat, count, credit) do
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
          stt = candidate(scope, STT)
          tts = candidate(scope, TTS)
          send(observer, {:waiting, self()})
          assert_receive {:go, ^gate}, 5_000
          samples = for round <- 1..@rounds, do: round(stt, tts, credit, round)
          started = now()
          close(tts)
          close(stt)
          %{samples: samples, close_us: now() - started}
        end)
      end)

    Enum.each(jobs, fn job ->
      pid = job.pid
      assert_receive {:waiting, ^pid}, 5_000
    end)

    before_memory = :erlang.memory(:total)
    Enum.each(jobs, &send(&1.pid, {:go, gate}))
    results = Enum.map(jobs, &Task.await(&1, 30_000))
    samples = Enum.flat_map(results, & &1.samples)

    Enum.each(scopes, fn {id, scope} ->
      assert %{active: 0} = DynamicSupervisor.count_children(scope.sessions)
      stop_supervised!(id)
    end)

    IO.puts(
      "TTS cancellation repeat=#{repeat} scopes=#{count} credit=#{credit}: #{length(samples)} cycles"
    )

    %{
      repeat: repeat,
      scopes: count,
      credit: credit,
      cancellation_cycles: length(samples),
      completed_replacements: length(samples),
      stt_turns: length(samples),
      metrics:
        Map.new(@metrics, fn key -> {key, stats(Enum.map(samples, &Map.fetch!(&1, key)))} end),
      close_both_us: stats(Enum.map(results, & &1.close_us)),
      memory_before_bytes: before_memory,
      memory_after_bytes: :erlang.memory(:total),
      process_count_after: :erlang.system_info(:process_count)
    }
  end

  defp round(stt, tts, credit, round) do
    {prefix, suffix, expected_t} = fixture()
    started = now()
    assert :ok = Session.push_audio(stt, prefix)
    event(stt, :speech_started)
    transcript = event(stt, :transcript)
    assert transcript.text == "E"
    stt_text_us = now() - started

    started = now()
    assert {:ok, %{ref: request}} = Session.speak(tts, "E")
    assert event(tts, :input_submitted).request_ref == request
    first = audio(tts, request)
    assert first.payload == binary_part(prefix, 0, 320)
    first_audio_us = now() - started

    held =
      case credit do
        :pending ->
          first

        :credited ->
          assert :ok = Session.ack_audio(tts, first)
          second = audio(tts, request)
          assert second.payload == :binary.copy(<<0>>, 320)
          second
      end

    started = now()
    assert :ok = Session.push_audio(stt, suffix)
    ended = event(stt, :turn_ended)
    assert ended.text == "E"
    assert ended.turn_ref == transcript.turn_ref
    stt_end_us = now() - started
    assert :ok = Session.validate_audio(tts, held)

    started = now()
    assert {:ok, ticket} = Session.fence_output(tts, request)
    fence_us = now() - started
    assert {:error, :stale_audio} = Session.validate_audio(tts, held)
    assert {:error, :stale_audio} = Session.ack_audio(tts, held)
    channel = GenServer.whereis(Channel.address(tts))

    # A controlled report, deliberately independent of generated/credited duration.
    started = now()
    assert {:ok, playback} = Session.cancel(tts, ticket, 10)
    cancel_return_us = now() - started
    assert playback.request_ref == request
    assert playback.request_played_ms == 10
    assert playback.session_played_ms == round * 10
    assert event(tts, :cancelled).request_ref == request
    cancel_terminal_us = now() - started
    assert {:ok, ^playback} = Session.cancel(tts, ticket, 10)
    assert {:ok, ^ticket} = Session.fence_output(tts, request)
    refute_received {:vxpipe_speech_audio, %{session: ^tts, request_ref: ^request}}

    started = now()
    assert {:ok, %{ref: replacement}} = Session.speak(tts, "T")
    assert replacement != request
    assert event(tts, :input_submitted).request_ref == replacement
    provider = Session.provider(tts)
    send(provider, {:vxpipe_speech_credit, channel, request, held.ref, :ok})
    send(provider, {:emit, request})
    send(channel, {:credit_expired, held.ref})

    {pcm, first_us, sink_end_us} = drain(tts, replacement, started, [], nil, nil)
    generation_end_us = now() - started
    assert pcm == expected_t
    assert {:error, :stale_audio} = Session.ack_audio(tts, held)

    # Generation has completed. Cancelling its remaining sink lifetime must not
    # fabricate another terminal or infer playback from the fully credited bytes.
    assert {:ok, completed_ticket} = Session.fence_output(tts, replacement)
    assert {:ok, completed_playback} = Session.cancel(tts, completed_ticket, 0)
    assert completed_playback.request_ref == replacement
    assert completed_playback.request_played_ms == 0
    assert completed_playback.session_played_ms == round * 10
    assert {:ok, ^completed_playback} = Session.cancel(tts, completed_ticket, 0)
    assert {:ok, ^completed_ticket} = Session.fence_output(tts, replacement)
    assert {:error, :stale_cancellation} = Session.cancel(tts, ticket, 10)
    refute_received {:vxpipe_speech, %Event{session: ^tts}}

    %{
      first_audio_us: first_audio_us,
      fence_us: fence_us,
      cancel_return_us: cancel_return_us,
      cancel_terminal_us: cancel_terminal_us,
      replacement_first_audio_us: first_us,
      replacement_generation_end_us: generation_end_us,
      replacement_sink_acceptance_end_us: sink_end_us,
      stt_text_us: stt_text_us,
      stt_end_us: stt_end_us
    }
  end

  defp candidate(scope, provider) do
    {:ok, allocation, :starting} =
      Session.start(scope,
        provider: provider,
        options: @settings,
        private: [emit_interval_ms: 0]
      )

    event(allocation, :ready)
    allocation
  end

  defp audio(allocation, request) do
    assert_receive {:vxpipe_speech_audio, %{session: ^allocation} = audio}, 5_000
    assert audio.request_ref == request
    assert byte_size(audio.payload) == 320
    assert :ok = Session.validate_audio(allocation, audio)
    audio
  end

  defp drain(allocation, request, started, chunks, first_us, sink_end_us) do
    receive do
      {:vxpipe_speech_audio, %{session: ^allocation} = audio} ->
        assert audio.request_ref == request
        assert byte_size(audio.payload) == 320
        first_us = first_us || now() - started
        assert :ok = Session.validate_audio(allocation, audio)
        assert :ok = Session.ack_audio(allocation, audio)
        drain(allocation, request, started, [audio.payload | chunks], first_us, now() - started)

      {:vxpipe_speech, %Event{session: ^allocation, kind: :completed} = completed} ->
        assert completed.request_ref == request
        assert :ok = Session.ack(allocation, completed)
        assert length(chunks) == 17
        {chunks |> Enum.reverse() |> IO.iodata_to_binary(), first_us, sink_end_us}

      {:vxpipe_speech, %Event{session: ^allocation}} ->
        flunk("unexpected or duplicate control event")
    after
      5_000 -> flunk("replacement output stalled")
    end
  end

  defp event(allocation, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation} = event}, 5_000
    assert event.kind == kind
    assert event.generation == allocation.generation
    assert :ok = Session.ack(allocation, event)
    event
  end

  defp close(allocation) do
    pids = [
      Session.tree(allocation),
      Session.provider(allocation),
      GenServer.whereis(Channel.address(allocation))
    ]

    monitors = Enum.map(pids, &{&1, Process.monitor(&1)})
    assert :ok = Session.close(allocation)

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    end
  end

  defp fixture do
    dash =
      for index <- 0..479, into: <<>> do
        sample = round(:math.sin(2.0 * :math.pi() * 700 / 8_000 * index) * 4_096)
        <<sample::signed-little-16>>
      end

    prefix = binary_part(dash, 0, 320) <> :binary.copy(<<0, 0>>, 480)
    suffix = :binary.copy(<<0, 0>>, 1_760)
    {prefix, suffix, dash <> :binary.copy(<<0, 0>>, 2_240)}
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
