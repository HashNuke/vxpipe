# From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/speech_faults.exs /tmp/speech-faults.json
# Isolated native STT trees, with explicit replacement; no automatic recovery.
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.SpeechFaultsBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Input, Session, SessionTree}

  @report List.first(System.argv()) || "/tmp/speech-faults.json"
  @failures [
    :provider,
    :channel,
    :input,
    :providers,
    :initializers,
    :control,
    :admissions,
    :sessions
  ]
  @shared [:control, :admissions, :sessions]
  @rounds 40

  @tag timeout: 120_000
  @tag :capture_log
  test "fault containment and explicit replacement while healthy peers recognize PCM" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    capabilities =
      start_supervised!(
        {DynamicSupervisor, name: __MODULE__.Capabilities, strategy: :one_for_one}
      )

    trials =
      for repeat <- 1..3, count <- [1, 8, 32], failure <- @failures do
        trial(tasks, capabilities, repeat, count, failure)
      end

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      workload:
        "unpaced native Morse E; 1/8/32 healthy allocations plus one fault allocation; 40 turns per healthy peer; three repeats; asynchronous fault/replacement begins after first text in round 20; healthy rounds continue independently; interval overlap counts recorded",
      safe_observation:
        "allocation failures use a safe closed event; shared failures use capability DOWN; teardown additionally observes owned provider, input, and allocation tree DOWN",
      trials: trials,
      summaries:
        trials
        |> Enum.group_by(&{&1.concurrency, &1.failure})
        |> Enum.map(fn {{count, failure}, rows} ->
          %{
            concurrency: count,
            failure: failure,
            safe_us: stats(Enum.map(rows, & &1.safe_us)),
            teardown_us: stats(Enum.map(rows, & &1.teardown_us)),
            replacement_ready_us: stats(Enum.map(rows, & &1.replacement_ready_us)),
            fault_round_end_us: stats(Enum.flat_map(rows, & &1.fault_round_end_us))
          }
        end)
    }

    File.write!(@report, JSON.encode!(report))
    IO.puts("Fault timing report written to #{@report}; #{length(trials)} trials")
  end

  defp trial(tasks, capabilities, repeat, count, failure) do
    observer = self()
    scopes = for _ <- 1..count, do: scope(capabilities, observer)
    {failed_id, failed_scope} = scope(capabilities, observer)

    fault_job =
      Task.Supervisor.async_nolink(tasks, fn ->
        failed = start_session(failed_scope)
        send(observer, {:fault_ready, self()})
        assert_receive :inject, 5_000
        monitors = monitors(failed_scope, failed, failure)
        inject(capabilities, observer, failed_id, failed_scope, failed, failure, monitors)
      end)

    fault_pid = fault_job.pid
    assert_receive {:fault_ready, ^fault_pid}, 5_000

    jobs =
      for {_id, scope} <- scopes do
        Task.Supervisor.async_nolink(tasks, fn -> worker(scope, observer) end)
      end

    Enum.each(jobs, fn job ->
      pid = job.pid
      assert_receive {:ready, ^pid}, 5_000
    end)

    {samples, fault_round} =
      Enum.reduce(1..@rounds, {[], []}, fn round, {samples, fault_round} ->
        Enum.each(jobs, &send(&1.pid, {:prefix, round}))

        texts =
          Enum.map(jobs, fn job ->
            pid = job.pid
            assert_receive {:text, ^pid, ^round, sample}, 5_000
            sample
          end)

        Enum.each(jobs, &send(&1.pid, {:suffix, round}))
        if round == 20, do: send(fault_job.pid, :inject)

        ends =
          Enum.map(jobs, fn job ->
            pid = job.pid
            assert_receive {:ended, ^pid, ^round, sample}, 5_000
            sample
          end)

        fault_round = if round == 20, do: Enum.map(ends, & &1.end_us), else: fault_round
        {samples ++ Enum.zip_with(texts, ends, &Map.merge/2), fault_round}
      end)

    Enum.each(jobs, fn job ->
      send(job.pid, :finish)
      assert :ok = Task.await(job, 5_000)
    end)

    Enum.each(scopes, fn {id, scope} ->
      assert DynamicSupervisor.which_children(scope.sessions) == []
      :ok = DynamicSupervisor.terminate_child(capabilities, id)
    end)

    fault = Task.await(fault_job, 5_000)
    :ok = DynamicSupervisor.terminate_child(capabilities, fault.replacement_scope_id)
    assert DynamicSupervisor.which_children(capabilities) == []

    intervals =
      Enum.flat_map(samples, fn sample -> [sample.prefix_interval, sample.suffix_interval] end)

    overlap = fn first, last ->
      Enum.count(intervals, fn {a, b} -> a <= last and b >= first end)
    end

    Map.merge(
      Map.drop(fault, [:replacement_scope_id, :fault_started, :replacement_started, :ready_at]),
      %{
        fault_round_end_us: fault_round,
        input_intervals_during_failure: overlap.(fault.fault_started, fault.replacement_started),
        input_intervals_during_replacement: overlap.(fault.replacement_started, fault.ready_at),
        concurrency: count,
        repeat: repeat,
        failure: failure,
        turns: length(samples),
        healthy_text_us: stats(Enum.map(samples, & &1.text_us)),
        healthy_end_us: stats(Enum.map(samples, & &1.end_us)),
        audio_accept_us: stats(Enum.flat_map(samples, & &1.audio_us)),
        processes_after: :erlang.system_info(:process_count),
        memory_after: :erlang.memory(:total)
      }
    )
  end

  defp monitors(scope, allocation, failure) do
    pids = [
      Session.tree(allocation),
      Session.provider(allocation),
      GenServer.whereis(Input.address(allocation))
    ]

    pids = if failure in @shared, do: [scope.tree | pids], else: pids
    Map.new(pids, &{&1, Process.monitor(&1)})
  end

  defp inject(capabilities, observer, id, scope, allocation, failure, monitors) do
    target =
      case failure do
        :provider -> Session.provider(allocation)
        :channel -> GenServer.whereis(Channel.address(allocation))
        :input -> GenServer.whereis(Input.address(allocation))
        :providers -> GenServer.whereis(SessionTree.providers(allocation))
        :initializers -> GenServer.whereis(SessionTree.commands(allocation))
        :control -> scope.control
        :admissions -> scope.admissions
        :sessions -> scope.sessions
      end

    started = now()
    Process.exit(target, :kill)

    monitors =
      if failure in @shared do
        monitor = Map.fetch!(monitors, scope.tree)
        tree = scope.tree
        assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 1_000
        Map.delete(monitors, tree)
      else
        assert_receive {:vxpipe_speech_closed, ^allocation, :session_failed}, 1_000
        monitors
      end

    safe = now() - started

    Enum.each(monitors, fn {pid, monitor} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)

    teardown = now() - started
    # Registry cleanup can trail the exact :DOWN signals; a stale dead PID is not
    # a restarted child. All returned PIDs must be ones just observed terminating.
    for pid <- [Session.tree(allocation), Session.provider(allocation)], not is_nil(pid) do
      assert Map.has_key?(monitors, pid)
    end

    replacement_started = now()

    {replacement_id, replacement_scope} =
      if failure in @shared do
        scope(capabilities, observer)
      else
        _ = :sys.get_state(scope.control)
        {id, scope}
      end

    replacement = start_session(replacement_scope)
    ready_at = now()
    ready = ready_at - replacement_started
    {prefix, suffix} = pcm()
    assert :ok = Session.push_audio(replacement, prefix)
    event(replacement, :speech_started)
    event(replacement, :transcript)
    assert :ok = Session.push_audio(replacement, suffix)
    event(replacement, :turn_ended)
    assert :ok = Session.close(replacement)

    %{
      safe_us: safe,
      fault_started: started,
      replacement_started: replacement_started,
      ready_at: ready_at,
      teardown_us: teardown,
      replacement_ready_us: ready,
      replacement_scope_id: replacement_id
    }
  end

  defp worker(scope, observer) do
    allocation = start_session(scope)
    send(observer, {:ready, self()})
    rounds(allocation, observer, pcm())
  end

  defp rounds(allocation, observer, {prefix, suffix} = pcm) do
    receive do
      {:prefix, round} ->
        started = now()
        assert :ok = Session.push_audio(allocation, prefix)
        audio = now() - started
        event(allocation, :speech_started)
        event(allocation, :transcript)
        finished = now()

        send(
          observer,
          {:text, self(), round,
           %{text_us: finished - started, prefix_interval: {started, finished}}}
        )

        assert_receive {:suffix, ^round}, 5_000
        started = now()
        assert :ok = Session.push_audio(allocation, suffix)
        tail_audio = now() - started
        event(allocation, :turn_ended)

        finished = now()

        send(
          observer,
          {:ended, self(), round,
           %{
             end_us: finished - started,
             suffix_interval: {started, finished},
             audio_us: [audio, tail_audio]
           }}
        )

        rounds(allocation, observer, pcm)

      :finish ->
        Session.close(allocation)
    after
      5_000 -> flunk("coordinator did not release healthy peer")
    end
  end

  defp event(allocation, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event}, 5_000
    if kind != :speech_started, do: assert(event.text == "E")
    assert :ok = Session.ack(allocation, event)
  end

  defp scope(capabilities, owner) do
    {:ok, tree} = DynamicSupervisor.start_child(capabilities, {CapabilityTree, owner: owner})
    {tree, CapabilityTree.scope(tree)}
  end

  defp start_session(scope) do
    assert {:ok, allocation, :starting} = Session.start(scope, provider: MorseSession)
    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}, 5_000
    assert :ok = Session.ack(allocation, ready)
    allocation
  end

  defp pcm do
    dot =
      for i <- 0..959, into: <<>> do
        sample = if rem(div(i, 11), 2) == 0, do: 3_000, else: -3_000
        <<sample::signed-little-16>>
      end

    {dot <> :binary.copy(<<0, 0>>, 2_880), :binary.copy(<<0, 0>>, 10_560)}
  end

  defp now, do: System.monotonic_time(:microsecond)

  defp stats(values) do
    values = Enum.sort(values)

    %{
      n: length(values),
      p50: percentile(values, 0.5),
      p95: percentile(values, 0.95),
      p99: percentile(values, 0.99),
      max: List.last(values)
    }
  end

  defp percentile(values, fraction),
    do: Enum.at(values, max(ceil(length(values) * fraction) - 1, 0))
end
