defmodule Vxpipe.CallEngine.Diagnostics.SettingsProjection do
  @moduledoc "Direct, expiring local settings reads with one bounded background IO slot."
  use GenServer
  alias Vxpipe.CallEngine.Diagnostics.SettingsLease
  @interval 1_000

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :projection))

  def status(name) do
    # Read the hint first: publishing its revocation clears the flag only after
    # replacing the lease. Reading the lease first could pair old data with zero.
    with [{:invalidation, _owner, flag}] <- :ets.lookup(name, :invalidation),
         0 <- :atomics.get(flag, 1),
         [{:lease, lease, clock, epoch}] <- :ets.lookup(name, :lease) do
      observed_status(lease, clock.(), epoch)
    else
      1 -> {:unavailable, :invalidated}
      _ -> {:unavailable, :settings_unavailable}
    end
  rescue
    _ -> {:unavailable, :settings_unavailable}
  catch
    _, _ -> {:unavailable, :settings_unavailable}
  end

  @doc "An enabled revision and publication epoch; consumers must also retain their lease deadline."
  def grant(name) do
    case grant_snapshot(name) do
      {:ok, grant, _now, _expires_at} -> {:ok, grant}
      error -> error
    end
  end

  @doc "One local authority snapshot with sampled monotonic time and its finite deadline."
  def grant_snapshot(name) do
    with [{:invalidation, _owner, flag}] <- :ets.lookup(name, :invalidation),
         0 <- :atomics.get(flag, 1),
         [{:lease, lease, clock, epoch}] <- :ets.lookup(name, :lease),
         now = clock.(),
         {:enabled, revision} <- observed_status(lease, now, epoch),
         0 <- :atomics.get(epoch, 1) do
      {:ok, {revision, epoch}, now, lease.expires_at}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  @doc "Coalesced revocation hint. Only a subsequent durable read may grant authority."
  def invalidate(name) do
    case :ets.lookup(name, :invalidation) do
      [{:invalidation, owner, flag}] ->
        if :atomics.compare_exchange(flag, 1, 0, 1) == :ok,
          do: Process.send(owner, :invalidate_settings, [:nosuspend])

        :ok

      [] ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    name = Keyword.fetch!(options, :projection)
    reader = Process.whereis(Keyword.fetch!(options, :reader))
    flag = :atomics.new(1, signed: false)
    :ets.new(name, [:named_table, :set, :protected, read_concurrency: true])
    :ets.insert(name, {:invalidation, self(), flag})

    state = %{
      name: name,
      reader: reader,
      reader_ref: Process.monitor(reader),
      flag: flag,
      clock: Keyword.fetch!(options, :clock),
      send_after: Keyword.fetch!(options, :send_after),
      lease: SettingsLease.new(Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)),
      poll: nil,
      job: nil,
      last_started: nil
    }

    {:ok, publish(state), {:continue, :read}}
  end

  @impl true
  def handle_continue(:read, state), do: {:noreply, state |> start_read() |> schedule()}

  @impl true
  def handle_info({:poll, token}, %{poll: token} = state),
    do: {:noreply, state |> start_read() |> schedule()}

  def handle_info({:read_timeout, token}, %{job: %{token: token} = job} = state) do
    next = %{
      state
      | job: %{job | discard?: true},
        lease: SettingsLease.revoke(state.lease, :read_timeout)
    }

    {:noreply, publish(next)}
  end

  def handle_info({:settings_result, token, result}, %{job: %{token: token} = job} = state) do
    Process.cancel_timer(job.timer)
    now = state.clock.()

    lease =
      cond do
        job.discard? -> state.lease
        now - job.started >= @interval -> SettingsLease.revoke(state.lease, :read_timeout)
        true -> accept(state, job.started, result, now)
      end

    {:noreply, publish(%{state | job: nil, lease: lease})}
  end

  def handle_info(:invalidate_settings, state) do
    job = if state.job, do: %{state.job | discard?: true}

    next = publish(%{state | job: job, lease: SettingsLease.revoke(state.lease, :invalidated)})
    :atomics.put(state.flag, 1, 0)
    {:noreply, next}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{reader_ref: ref} = state),
    do:
      {:noreply,
       publish(%{
         state
         | reader: nil,
           lease: SettingsLease.revoke(state.lease, :settings_unavailable)
       })}

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, :redacted)
      |> Map.put(:message, :redacted)
      |> Map.put(:reason, :redacted)
      |> Map.put(:log, [])

  defp start_read(%{job: job} = state) when not is_nil(job), do: state
  defp start_read(%{reader: nil} = state), do: state

  defp start_read(state) do
    now = state.clock.()

    if state.last_started == nil or now - state.last_started >= @interval do
      token = make_ref()
      send(state.reader, {:read_settings, self(), token})
      timer = state.send_after.(self(), {:read_timeout, token}, @interval)

      %{
        state
        | job: %{token: token, started: now, timer: timer, discard?: false},
          last_started: now
      }
    else
      state
    end
  end

  defp accept(state, started, {:ok, snapshot}, now) do
    case SettingsLease.accept(state.lease, snapshot, started, now, state.lease.clock_id) do
      {:ok, lease} -> lease
      {:error, _reason, lease} -> lease
    end
  end

  defp accept(state, _started, _error, _now),
    do: SettingsLease.revoke(state.lease, :settings_unavailable)

  defp publish(state) do
    epoch = continuous_epoch(state)
    :ets.insert(state.name, {:lease, state.lease, state.clock, epoch})
    state
  end

  defp continuous_epoch(state) do
    now = state.clock.()
    current = SettingsLease.status(state.lease, now, state.lease.clock_id)

    with {:enabled, revision} <- current,
         [{:lease, previous, _clock, epoch}] <- :ets.lookup(state.name, :lease),
         {:enabled, ^revision} <- observed_status(previous, now, epoch),
         0 <- :atomics.get(epoch, 1) do
      epoch
    else
      _ -> :atomics.new(1, signed: false)
    end
  end

  defp observed_status(lease, now, epoch) do
    status = SettingsLease.status(lease, now, lease.clock_id)
    # Retire shared authority before returning expiry to a reader. A publisher
    # preempted after sampling time cannot make this epoch valid again.
    if not match?({:enabled, _}, status), do: :atomics.put(epoch, 1, 1)
    status
  end

  defp schedule(state) do
    token = make_ref()
    _ = state.send_after.(self(), {:poll, token}, @interval)
    %{state | poll: token}
  end
end
