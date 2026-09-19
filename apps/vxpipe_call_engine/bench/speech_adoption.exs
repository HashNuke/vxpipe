# From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/speech_adoption.exs /tmp/speech-adoption.json
# Isolated native STT trees; no hosted providers or production calls.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.SpeechAdoptionBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionOwner

  @report List.first(System.argv()) || "/tmp/speech-adoption.json"
  @metrics [
    :ready_us,
    :stale_close_us,
    :close_us,
    :healthy_text_us,
    :healthy_end_us,
    :candidate_text_us,
    :candidate_end_us
  ]

  @tag timeout: 300_000
  @tag :capture_log
  test "adoption churn preserves active siblings under burst and paced PCM load" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    actors =
      start_supervised!({DynamicSupervisor, name: __MODULE__.Actors, strategy: :one_for_one})

    trials =
      for pacing <- [:burst, :paced],
          repeat <- 1..3,
          count <- [1, 8, 32],
          mode <- if(rem(repeat, 2) == 1, do: [:direct, :adopted], else: [:adopted, :direct]) do
        trial(tasks, actors, pacing, repeat, count, mode)
      end

    summaries =
      trials
      |> Enum.group_by(&{&1.pacing, &1.scopes, &1.mode})
      |> Enum.map(fn {{pacing, scopes, mode}, group} ->
        %{
          pacing: pacing,
          scopes: scopes,
          mode: mode,
          turns: Enum.sum(Enum.map(group, & &1.turns)),
          metrics: summarize(Enum.flat_map(group, & &1.samples))
        }
      end)

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      burst_rounds: 30,
      paced_rounds: 3,
      warmup_rounds: 1,
      repeats: 3,
      workload:
        "1/8/32 local scopes, each with one active STT and one transient candidate; 20ms PCM chunks with a 20ms wait after each completed push, plus processing; active input pauses during candidate churn",
      fixture:
        "independent E, 16kHz mono PCM16; exact start/transcript/end and generation checks",
      summaries: summaries,
      trials: Enum.map(trials, &Map.delete(&1, :samples))
    }

    File.write!(@report, JSON.encode!(report))
    Enum.each(summaries, fn row -> IO.inspect(row, label: "adoption load") end)
    IO.puts("Adoption load report written to #{@report}")
  end

  defp trial(tasks, actors, pacing, repeat, count, mode) do
    observer = self()

    scopes =
      for _ <- 1..count do
        id = make_ref()
        tree = start_supervised!(Supervisor.child_spec({CapabilityTree, owner: observer}, id: id))
        {id, CapabilityTree.scope(tree)}
      end

    rounds = if pacing == :burst, do: 30, else: 3
    gate = make_ref()

    jobs =
      Enum.map(scopes, fn {_id, scope} ->
        Task.Supervisor.async_nolink(tasks, fn ->
          worker(scope, actors, observer, gate, pacing, mode)
        end)
      end)

    Enum.each(jobs, fn task ->
      pid = task.pid
      assert_receive {:worker_ready, ^pid}, 5_000
    end)

    before_memory = :erlang.memory(:total)

    samples =
      for round <- 0..rounds, reduce: [] do
        samples ->
          Enum.each(jobs, &send(&1.pid, {:round, gate}))

          results =
            Enum.map(jobs, fn task ->
              pid = task.pid
              assert_receive {:round_done, ^pid, result}, 10_000
              result
            end)

          if round == 0, do: samples, else: results ++ samples
      end

    Enum.each(jobs, &send(&1.pid, {:finish, gate}))
    Enum.each(jobs, &Task.await(&1, 5_000))

    Enum.each(scopes, fn {id, scope} ->
      assert %{active: 0} = DynamicSupervisor.count_children(scope.sessions)
      stop_supervised!(id)
    end)

    assert %{active: 0} = DynamicSupervisor.count_children(actors)
    assert length(samples) == count * rounds

    assert Enum.all?(samples, fn sample -> Enum.all?(@metrics, &(Map.fetch!(sample, &1) >= 0)) end)

    IO.puts(
      "#{pacing} repeat=#{repeat} scopes=#{count} mode=#{mode}: #{2 * length(samples)} exact turns"
    )

    %{
      pacing: pacing,
      repeat: repeat,
      scopes: count,
      mode: mode,
      turns: 2 * length(samples),
      samples: samples,
      metrics: summarize(samples),
      memory_before_bytes: before_memory,
      memory_after_bytes: :erlang.memory(:total),
      process_count_after: :erlang.system_info(:process_count)
    }
  end

  defp worker(scope, actors, observer, gate, pacing, mode) do
    {:ok, active, :starting} = Session.start(scope, provider: MorseSession)
    ready(active)
    send(observer, {:worker_ready, self()})
    rounds(scope, actors, observer, gate, pacing, mode, active)
    close(active)
  end

  defp rounds(scope, actors, observer, gate, pacing, mode, active) do
    receive do
      {:round, ^gate} ->
        {prefix, suffix} = reference_e()
        healthy_prefix = push(active, prefix, pacing)
        event(active, :speech_started)
        healthy_started = event(active, :transcript)
        healthy_text = now() - healthy_prefix

        {candidate, ready_us, stale_close_us} = candidate(scope, actors, mode)
        candidate_prefix = push(candidate, prefix, pacing)
        event(candidate, :speech_started)
        candidate_started = event(candidate, :transcript)
        candidate_text = now() - candidate_prefix
        candidate_suffix = push(candidate, suffix, pacing)
        candidate_end = event(candidate, :turn_ended)
        assert candidate_end.turn_ref == candidate_started.turn_ref
        candidate_end_us = now() - candidate_suffix

        healthy_suffix = push(active, suffix, pacing)
        healthy_end = event(active, :turn_ended)
        assert healthy_end.turn_ref == healthy_started.turn_ref
        healthy_end_us = now() - healthy_suffix
        close_started = now()
        close(candidate)
        close_us = now() - close_started
        refute_received {:vxpipe_speech_closed, ^active, _reason}
        refute_received {:vxpipe_speech, %Event{session: ^candidate}}

        send(
          observer,
          {:round_done, self(),
           %{
             ready_us: ready_us,
             stale_close_us: stale_close_us,
             close_us: close_us,
             healthy_text_us: healthy_text,
             healthy_end_us: healthy_end_us,
             candidate_text_us: candidate_text,
             candidate_end_us: candidate_end_us
           }}
        )

        rounds(scope, actors, observer, gate, pacing, mode, active)

      {:finish, ^gate} ->
        :ok
    after
      10_000 -> flunk("missing benchmark round")
    end
  end

  defp candidate(scope, _actors, :direct) do
    started = now()
    {:ok, allocation, :starting} = Session.start(scope, provider: MorseSession)
    ready(allocation)
    {allocation, now() - started, 0}
  end

  defp candidate(scope, actors, :adopted) do
    consumer = self()
    {:ok, lease} = DynamicSupervisor.start_child(actors, {SpeechSessionOwner, consumer})
    lease_monitor = Process.monitor(lease)
    started = now()

    {:ok, allocation, :starting} =
      SpeechSessionOwner.run(lease, fn _state ->
        Session.start(scope,
          provider: MorseSession,
          owner: consumer,
          consumer: nil,
          lease: self()
        )
      end)

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _descriptor}},
                   5_000

    tree = Session.tree(allocation)

    assert :ok =
             SpeechSessionOwner.run(lease, fn _state -> Session.adopt(allocation, consumer) end)

    ready(allocation)
    ready_us = now() - started
    assert Session.tree(allocation) == tree
    cancel_started = now()

    assert {:error, :not_owner} =
             SpeechSessionOwner.run(lease, fn _state -> Session.close(allocation) end)

    stale_close_us = now() - cancel_started
    :ok = DynamicSupervisor.terminate_child(actors, lease)
    assert_receive {:DOWN, ^lease_monitor, :process, ^lease, _reason}
    {allocation, ready_us, stale_close_us}
  end

  defp ready(allocation) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}, 5_000
    assert :ok = Session.ack(allocation, ready)
  end

  defp event(allocation, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation} = event}, 5_000
    assert event.kind == kind
    assert event.generation == allocation.generation
    if kind != :speech_started, do: assert(event.text == "E")
    assert :ok = Session.ack(allocation, event)
    event
  end

  defp close(allocation) do
    tree = Session.tree(allocation)
    provider = Session.provider(allocation)
    tree_monitor = Process.monitor(tree)
    provider_monitor = Process.monitor(provider)
    assert :ok = Session.close(allocation)
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
  end

  defp push(allocation, pcm, :burst) do
    started = now()
    assert :ok = Session.push_audio(allocation, pcm)
    started
  end

  defp push(allocation, pcm, :paced), do: paced(allocation, pcm)

  defp paced(allocation, <<chunk::binary-size(640), rest::binary>>) do
    started = now()
    assert :ok = Session.push_audio(allocation, chunk)

    if rest == <<>> do
      started
    else
      tick = make_ref()
      Process.send_after(self(), {:pcm_tick, tick}, 20)
      assert_receive {:pcm_tick, ^tick}, 1_000
      paced(allocation, rest)
    end
  end

  defp reference_e do
    dot =
      for i <- 0..959, into: <<>> do
        sample = if rem(div(i, 11), 2) == 0, do: 3_000, else: -3_000
        <<sample::signed-little-16>>
      end

    {dot <> :binary.copy(<<0, 0>>, 3 * 960), :binary.copy(<<0, 0>>, 11 * 960)}
  end

  defp summarize(samples),
    do: Map.new(@metrics, fn key -> {key, stats(Enum.map(samples, &Map.fetch!(&1, key)))} end)

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
