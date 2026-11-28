defmodule Vxpipe.CallEngine.Speech.Silero.Pool do
  @moduledoc false
  use GenServer
  alias Vxpipe.CallEngine.Speech.Silero.Lease

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  def reserve(generation, deadline, server \\ __MODULE__) do
    with true <- deadline > System.monotonic_time(:millisecond),
         {:ok, lease} <- Lease.offer(server, generation) do
      try do
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining > 0 do
          GenServer.call(lease.pool, {:adopt, lease, deadline}, remaining)
        else
          Lease.withdraw(lease)
          {:error, :model_unavailable}
        end
      catch
        :exit, _ ->
          GenServer.cast(lease.pool, {:abandon, lease})
          {:error, :model_unavailable}
      end
    else
      false -> {:error, :model_unavailable}
      error -> error
    end
  end

  def submit(%Lease{owner: owner} = lease, position, model, {pcm, packed} = row, deadline)
      when owner == self() and byte_size(pcm) == 1024 and byte_size(packed) == 1280 do
    ref = {lease.pool, lease.generation, position, make_ref()}
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      remaining <= 0 ->
        {:error, :classification_timeout}

      Lease.submit(lease) ->
        GenServer.call(lease.pool, {:submit, lease, ref, model, row, deadline}, remaining)

      true ->
        {:error, :busy}
    end
  rescue
    ArgumentError -> {:error, :unknown_lease}
  catch
    :exit, {:timeout, _} -> {:error, :classification_timeout}
    :exit, _ -> {:error, :classification_failed}
  end

  def submit(_, _, _, _, _), do: {:error, :invalid_row}

  def cancel(%Lease{} = lease, ref) do
    GenServer.call(lease.pool, {:cancel, lease, ref})
  catch
    :exit, _ -> {:error, :unknown_job}
  end

  def close(%Lease{} = lease) do
    GenServer.call(lease.pool, {:close, lease})
  catch
    :exit, _ -> {:error, :unknown_lease}
  end

  @impl true
  def init(opts) do
    budget = Keyword.fetch!(opts, :budget)
    capacity = budget.workers * Keyword.get(opts, :leases_per_worker, 128)
    table = Lease.open_table(Keyword.fetch!(opts, :name), capacity)
    Process.send_after(self(), :sweep_offers, 1_000)

    {:ok,
     %{
       budget: budget,
       workers: %{},
       table: table,
       capacity: capacity,
       leases: %{},
       ready: :queue.new(),
       jobs: %{},
       idle: [],
       running: %{}
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       budget: state.budget,
       active_workers: map_size(state.workers),
       admitted: map_size(state.leases),
       admission_limit: state.capacity,
       ready: :queue.len(state.ready),
       in_flight: Enum.sum(for {_, {_, tokens}} <- state.running, do: length(tokens)),
       retired: Enum.count(state.jobs, fn {_, job} -> job.retired end)
     }, state}
  end

  def handle_call({:adopt, lease, deadline}, {owner, _}, state) do
    if owner == lease.owner and lease.table == state.table and
         System.monotonic_time(:millisecond) < deadline and Lease.adopt(lease) do
      monitor = :erlang.monitor(:process, owner, [{:tag, {:lease_down, lease.token}}])
      {:reply, {:ok, lease}, put_in(state.leases[lease.token], {lease, monitor})}
    else
      Lease.withdraw(lease)
      {:reply, {:error, :model_unavailable}, state}
    end
  end

  def handle_call({:close, lease}, {owner, _}, state) do
    case state.leases[lease.token] do
      {^lease, _monitor} when lease.owner == owner -> {:reply, :ok, close_lease(state, lease)}
      _ -> {:reply, {:error, :unknown_lease}, state}
    end
  end

  def handle_call({:submit, lease, ref, model, row, deadline}, {owner, _}, state) do
    token = lease.token
    now = System.monotonic_time(:millisecond)

    case state.leases[token] do
      {^lease, _}
      when owner == lease.owner and not is_map_key(state.jobs, token) and deadline > now ->
        timer = Process.send_after(self(), {:expired, token, ref}, deadline - now)

        job = %{
          ref: ref,
          owner: owner,
          model: model,
          row: row,
          deadline: deadline,
          timer: timer,
          running: false,
          retired: false,
          closing: false,
          queued_at: System.monotonic_time()
        }

        state = %{
          state
          | ready: :queue.in(token, state.ready),
            jobs: Map.put(state.jobs, token, job)
        }

        {:reply, {:ok, ref}, dispatch(state)}

      {^lease, _} when deadline <= now ->
        Lease.settle(lease)
        {:reply, {:error, :classification_timeout}, state}

      {^lease, _} ->
        {:reply, {:error, :busy}, state}

      _ ->
        {:reply, {:error, :unknown_lease}, state}
    end
  end

  def handle_call({:cancel, lease, ref}, {owner, _}, state) do
    case state.jobs[lease.token] do
      %{ref: ^ref, owner: ^owner, retired: false} ->
        {:reply, :ok, retire(state, lease.token, false)}

      _ ->
        {:reply, {:error, :unknown_job}, state}
    end
  end

  def handle_call(:register_worker, {pid, _}, state) do
    {:reply, :ok,
     dispatch(%{
       state
       | workers: Map.put(state.workers, pid, Process.monitor(pid)),
         idle: [pid | state.idle]
     })}
  end

  @impl true
  def handle_cast({:abandon, lease}, state) do
    {:noreply, close_lease(state, lease)}
  end

  @impl true
  def handle_info(:sweep_offers, state) do
    # Only the dispatcher recycles abandoned offers. Queued calls retain their
    # slot while the dispatcher is suspended or overloaded.
    for {_, owner, _, :offered} = offer <- :ets.match_object(state.table, {:_, :_, :_, :offered}),
        not Process.alive?(owner),
        do: :ets.delete_object(state.table, offer)

    Process.send_after(self(), :sweep_offers, 1_000)
    {:noreply, state}
  end

  def handle_info({{:lease_down, token}, monitor, :process, _, _}, state) do
    case state.leases[token] do
      {lease, ^monitor} -> {:noreply, close_lease(state, lease)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, worker, _}, state) do
    if state.workers[worker] == monitor do
      state = %{
        state
        | workers: Map.delete(state.workers, worker),
          idle: List.delete(state.idle, worker)
      }

      {:noreply, settle(state, worker, :error)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:settled, worker, id, result, duration}, state) do
    case state.running[worker] do
      {^id, tokens} ->
        :telemetry.execute(
          [:vxpipe, :silero, :pool, :batch],
          %{rows: length(tokens), duration: duration},
          %{}
        )

        state = settle(state, worker, result)
        {:noreply, dispatch(%{state | idle: [worker | state.idle]})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:expired, token, ref}, state) do
    case state.jobs[token] do
      %{ref: ^ref, retired: false} = job ->
        send(job.owner, {:silero_result, ref, {:error, :classification_timeout}})
        {:noreply, retire(state, token, false)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def format_status(status),
    do: %{status | state: :pool, message: :redacted, reason: :redacted, log: []}

  defp dispatch(%{idle: []} = state), do: state

  defp dispatch(state) do
    {entries, state} = take_ready(state, [], 16)

    case entries do
      [] ->
        state

      [{_, first} | _] ->
        [worker | idle] = state.idle
        id = make_ref()
        tokens = Enum.map(entries, &elem(&1, 0))
        rows = Enum.map(entries, fn {_, job} -> job.row end)
        GenServer.cast(worker, {:batch, id, first.model, rows})

        jobs =
          Enum.reduce(entries, state.jobs, fn {token, job}, jobs ->
            Map.put(jobs, token, %{job | row: nil, model: nil, running: true})
          end)

        dispatch(%{
          state
          | idle: idle,
            running: Map.put(state.running, worker, {id, tokens}),
            jobs: jobs
        })
    end
  end

  defp take_ready(state, acc, 0), do: {Enum.reverse(acc), state}

  defp take_ready(state, acc, remaining) do
    case :queue.out(state.ready) do
      {{:value, token}, queue} ->
        job = Map.fetch!(state.jobs, token)
        state = %{state | ready: queue}

        if job.deadline <= System.monotonic_time(:millisecond) do
          send(job.owner, {:silero_result, job.ref, {:error, :classification_timeout}})
          take_ready(drop_job(state, token), acc, remaining)
        else
          take_ready(state, [{token, job} | acc], remaining - 1)
        end

      {:empty, _} ->
        {Enum.reverse(acc), state}
    end
  end

  defp settle(state, worker, result) do
    case Map.pop(state.running, worker) do
      {nil, _} ->
        state

      {{_id, tokens}, running} ->
        results =
          case result do
            {:ok, rows} when is_list(rows) and length(rows) == length(tokens) ->
              if Enum.all?(rows, &valid_result?/1), do: rows

            _ ->
              nil
          end

        Enum.zip(tokens, results || List.duplicate(:error, length(tokens)))
        |> Enum.reduce(%{state | running: running}, fn {token, value}, acc ->
          job = acc.jobs[token]

          acc = drop_job(acc, token)

          unless job.retired do
            reply =
              cond do
                System.monotonic_time(:millisecond) >= job.deadline ->
                  {:error, :classification_timeout}

                value == :error ->
                  {:error, :classification_failed}

                true ->
                  {p, packed} = value
                  {:ok, p, packed}
              end

            send(job.owner, {:silero_result, job.ref, reply})
          end

          if job.closing do
            {lease, _} = acc.leases[token]
            release(acc, lease)
          else
            if job.retired, do: send(job.owner, {:silero_retired, job.ref})
            acc
          end
        end)
    end
  end

  defp valid_result?({p, packed}),
    do: is_float(p) and p >= 0.0 and p <= 1.0 and is_binary(packed) and byte_size(packed) == 1280

  defp valid_result?(_), do: false

  defp close_lease(state, lease) do
    case state.jobs[lease.token] do
      %{running: true} -> retire(state, lease.token, true)
      nil -> release(state, lease)
      _ -> state |> retire(lease.token, true) |> release(lease)
    end
  end

  defp retire(state, token, closing) do
    job = state.jobs[token]
    Process.cancel_timer(job.timer)

    if job.running do
      put_in(state.jobs[token], %{job | retired: true, closing: closing})
    else
      unless closing, do: send(job.owner, {:silero_retired, job.ref})
      drop_job(%{state | ready: :queue.delete(token, state.ready)}, token)
    end
  end

  defp drop_job(state, token) do
    {lease, _} = Map.fetch!(state.leases, token)
    Lease.settle(lease)
    {job, jobs} = Map.pop!(state.jobs, token)
    Process.cancel_timer(job.timer)
    %{state | jobs: jobs}
  end

  defp release(state, lease) do
    case Map.pop(state.leases, lease.token) do
      {nil, _} ->
        state

      {{_, monitor}, leases} ->
        Process.demonitor(monitor, [:flush])
        Lease.release(lease)
        %{state | leases: leases}
    end
  end
end
