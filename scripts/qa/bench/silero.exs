# Run in a fresh packaged release VM using bin/vxpipe eval 'Code.require_file(...)'.
defmodule SileroBenchmark do
  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, ActivitySupervisor, Silero}
  alias Silero.{Batch, CPUBudget, ModelCache, Pool, Worker}

  def run do
    {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
    {:ok, model} = ModelCache.fetch()
    kind = System.fetch_env!("SILERO_VARIANT")
    shape = System.fetch_env!("SILERO_WORKLOAD")
    count = String.to_integer(System.fetch_env!("SILERO_STREAMS"))
    source = File.read!(System.fetch_env!("SILERO_PCM"))
    pcm = source <> :binary.copy(<<0>>, 51_200 - byte_size(source))
    budget = CPUBudget.detect()
    metrics = :ets.new(:metrics, [:public, :set])
    pool = start_pool(kind, budget, metrics)
    parent = self()

    clients =
      for index <- 0..(count - 1) do
        spawn_link(fn ->
          backend = prepare(kind, index, model)
          send(parent, :ready)

          listen(backend, parent, index, %{
            pending: "",
            scores: [],
            latency: [],
            inference: [],
            backlog: 0
          })
        end)
      end

    for _ <- clients, do: receive(do: (:ready -> :ok))
    memory_before = memory()
    cpu_before = cpu()
    start = System.monotonic_time(:microsecond)

    rounds =
      case shape do
        "round" ->
          rounds(clients, pcm)

        paced when paced in ["sync", "spread"] ->
          start_paced(clients, pcm, paced)
          []
      end

    results =
      for _ <- clients do
        receive do
          {:done, index, result} -> {index, result}
        after
          120_000 -> raise "client did not drain"
        end
      end

    elapsed = System.monotonic_time(:microsecond) - start
    cpu_us = cpu() - cpu_before
    memory_after = memory()
    ordered = Enum.sort(results) |> Enum.map(&elem(&1, 1))

    traces =
      Enum.map(ordered, fn result ->
        result.scores
        |> Enum.reverse()
        |> Enum.map(fn p -> <<p::float-little-32>> end)
        |> IO.iodata_to_binary()
      end)

    expected = if shape == "round", do: 96, else: div(3000 * 320, 1024)
    true = Enum.all?(traces, &(byte_size(&1) == expected * 4))
    File.write!(System.fetch_env!("SILERO_TRACE"), traces)

    if pool do
      %{ready: 0, admitted: 0, retired: 0, in_flight: 0} = Pool.status(__MODULE__.Pool)
      Supervisor.stop(pool)
    end

    report = %{
      variant: kind,
      workload: shape,
      streams: count,
      workers: budget.workers,
      windows: count * expected,
      round_us: stats(rounds),
      packets_us: stats(Enum.flat_map(ordered, & &1.latency)),
      inference_packets_us: stats(Enum.flat_map(ordered, & &1.inference)),
      max_mailbox: Enum.max(Enum.map(ordered, & &1.backlog)),
      cpu_us: cpu_us,
      elapsed_us: elapsed,
      memory_before: memory_before,
      memory_after: memory_after,
      batches: Map.new(:ets.tab2list(metrics), fn {key, value} -> {inspect(key), value} end)
    }

    IO.puts("SILERO_BENCH " <> JSON.encode!(report))
  end

  defp start_pool("scalar", _, _), do: nil

  defp start_pool(kind, budget, metrics) do
    cap =
      case kind do
        "cap1" -> 1
        "cap16" -> 16
      end

    :ok =
      :telemetry.attach_many(
        make_ref(),
        for(suffix <- [:batch, :dispatch, :outcome], do: [:vxpipe, :silero, :pool, suffix]),
        &__MODULE__.observe/4,
        metrics
      )

    pool = __MODULE__.Pool

    workers =
      for index <- 1..budget.workers,
          do: Supervisor.child_spec({Worker, {pool, &Batch.run/2}}, id: {Worker, index})

    {:ok, tree} =
      Supervisor.start_link([{Pool, [name: pool, budget: budget, batch_limit: cap]} | workers],
        strategy: :one_for_one
      )

    tree
  end

  def observe([_, _, _, :batch], %{rows: n, duration: elapsed}, _, table) do
    increment(table, {:batch, n}, 1)
    increment(table, :native_us, System.convert_time_unit(elapsed, :native, :microsecond))
  end

  def observe([_, _, _, :dispatch], %{queue_duration: elapsed}, _, table),
    do: increment(table, :queue_us, System.convert_time_unit(elapsed, :native, :microsecond))

  def observe([_, _, _, :outcome], _, %{outcome: kind}, table), do: increment(table, kind, 1)
  defp increment(table, key, amount), do: :ets.update_counter(table, key, {2, amount}, {key, 0})

  defp prepare("scalar", index, _) do
    name = fn role ->
      {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, index, role}}}
    end

    {:ok, tree} =
      ActivitySupervisor.start_link(
        name: name.(:tree),
        tasks: name.(:tasks),
        runtime: name.(:runtime)
      )

    {:scalar, tree, name.(:runtime), Silero.new()}
  end

  defp prepare(_, _, model) do
    {:ok, lease} =
      Pool.reserve(make_ref(), System.monotonic_time(:millisecond) + 5000, __MODULE__.Pool)

    {:pool, lease, model, Batch.initial_state()}
  end

  defp step({:scalar, tree, runtime, state}, pcm, _) do
    {:ok, ref} = ActivityRuntime.submit(state, pcm, runtime)

    receive do
      {:vxpipe_speech_activity, ^ref, {:ok, state, probabilities}} ->
        {{:scalar, tree, runtime, state}, probabilities}
    after
      5000 -> raise "scalar timeout"
    end
  end

  defp step({:pool, lease, model, packed}, frame, seq) do
    {:ok, ref} =
      Pool.submit(lease, seq, model, {frame, packed}, System.monotonic_time(:millisecond) + 2000)

    receive do
      {:silero_result, ^ref, {:ok, p, next}} -> {{:pool, lease, model, next}, [p]}
    after
      5000 -> raise "pool timeout"
    end
  end

  defp listen(backend, parent, index, data) do
    receive do
      {:packet, seq, pcm, due, round?} ->
        {next, scores, pending} =
          case backend do
            {:scalar, _, _, _} ->
              {next, scores} = step(backend, pcm, seq)
              {next, scores, ""}

            {:pool, _, _, _} ->
              case data.pending <> pcm do
                <<frame::binary-size(1024), rest::binary>> ->
                  {next, scores} = step(backend, frame, seq)
                  {next, scores, rest}

                partial ->
                  {backend, [], partial}
              end
          end

        elapsed = System.monotonic_time(:microsecond) - due
        sample? = if round?, do: seq >= 16, else: seq >= 100
        {:message_queue_len, depth} = Process.info(self(), :message_queue_len)

        updated = %{
          pending: pending,
          scores: scores ++ data.scores,
          backlog: max(data.backlog, depth),
          latency: if(sample?, do: [elapsed | data.latency], else: data.latency),
          inference:
            if(sample? and scores != [], do: [elapsed | data.inference], else: data.inference)
        }

        if round?, do: send(parent, :ack)
        listen(next, parent, index, updated)

      :stop ->
        case backend do
          {:scalar, tree, _, _} -> Supervisor.stop(tree)
          {:pool, lease, _, _} -> :ok = Pool.close(lease)
        end

        send(parent, {:done, index, data})
    end
  end

  defp rounds(clients, pcm) do
    times =
      for round <- 0..95 do
        started = System.monotonic_time(:microsecond)

        clients
        |> Enum.with_index()
        |> Enum.each(fn {pid, index} ->
          send(
            pid,
            {:packet, round, binary_part(pcm, rem(round + index, 50) * 1024, 1024), started, true}
          )
        end)

        for _ <- clients, do: receive(do: (:ack -> :ok))
        System.monotonic_time(:microsecond) - started
      end

    Enum.each(clients, &send(&1, :stop))
    Enum.drop(times, 16)
  end

  defp start_paced(clients, pcm, shape) do
    epoch = System.monotonic_time(:microsecond) + 150_000
    wrapped = pcm <> pcm

    clients
    |> Enum.with_index()
    |> Enum.each(fn {pid, index} ->
      phase = if shape == "spread", do: div(index * 32_000, length(clients)), else: 0

      spawn_link(fn ->
        for seq <- 0..2999 do
          due = epoch + seq * 10_000 + phase
          wait = due - System.monotonic_time(:microsecond)
          if wait > 0, do: Process.sleep(div(wait + 999, 1000))
          pcm = binary_part(wrapped, rem(index * 1024 + seq * 320, 51200), 320)
          send(pid, {:packet, seq, pcm, due, false})
        end

        send(pid, :stop)
      end)
    end)
  end

  defp stats([]), do: nil

  defp stats(values) do
    sorted = Enum.sort(values)
    n = length(values)
    q = fn q -> Enum.at(sorted, ceil(q * n) - 1) end

    %{
      count: n,
      p50: q.(0.5),
      p95: q.(0.95),
      p99: q.(0.99),
      over_10ms: Enum.count(values, &(&1 > 10_000))
    }
  end

  defp cpu do
    [_, value] = Regex.run(~r/^usage_usec (\d+)$/m, File.read!("/sys/fs/cgroup/cpu.stat"))
    String.to_integer(value)
  end

  defp memory,
    do: File.read!("/sys/fs/cgroup/memory.current") |> String.trim() |> String.to_integer()
end

SileroBenchmark.run()
