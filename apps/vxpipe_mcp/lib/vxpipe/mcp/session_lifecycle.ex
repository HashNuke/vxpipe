defmodule Vxpipe.MCP.SessionLifecycle do
  @moduledoc false

  use GenServer, restart: :temporary

  def name(integration),
    do: {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:session_lifecycle, integration}}}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :integration)))

  def ready(integration), do: GenServer.call(name(integration), :ready, 500)

  def begin_close(integration, client, caller, deadline),
    do:
      GenServer.call(
        name(integration),
        {:begin_close, client, caller, deadline},
        max(deadline - now(), 1)
      )

  def admit(integration, method, stage, permission) do
    GenServer.call(name(integration), {:admit, method, stage, permission}, 500)
  catch
    :exit, _reason -> {:error, :session_retired}
  end

  @impl true
  def init(opts) do
    caller = Keyword.fetch!(opts, :caller)
    host = Keyword.fetch!(opts, :host)
    deadline = Keyword.fetch!(opts, :deadline)

    if now() < deadline and Process.alive?(caller) and Process.alive?(host) do
      {:ok,
       %{
         integration: Keyword.fetch!(opts, :integration),
         caller: caller,
         host: host,
         monitors: [Process.monitor(caller), Process.monitor(host)],
         deadline: deadline,
         timer: Process.send_after(self(), :expired, max(deadline - now(), 0)),
         phase: :starting,
         client: nil,
         permission: nil,
         submitted: false
       }}
    else
      {:stop, :connection_failed}
    end
  end

  @impl true
  def handle_call(:ready, _from, %{phase: :active} = state), do: {:reply, :ok, state}

  def handle_call(:ready, _from, %{phase: :closing} = state),
    do: {:reply, {:error, :connection_failed}, state}

  def handle_call(:ready, from, state) do
    if now() < state.deadline and Process.alive?(state.caller) and Process.alive?(state.host) do
      Process.cancel_timer(state.timer)
      Enum.each(state.monitors, &Process.demonitor(&1, [:flush]))
      {:reply, :ok, %{state | phase: :active, monitors: [], timer: nil}}
    else
      GenServer.reply(from, {:error, :connection_failed})
      cancel(state)
    end
  end

  def handle_call({:begin_close, _client, _caller, _deadline}, _from, %{phase: :closing} = state),
    do: {:reply, :closing, state}

  def handle_call({:begin_close, client, caller, deadline}, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    Enum.each(state.monitors, &Process.demonitor(&1, [:flush]))
    permission = make_ref()

    next = %{
      state
      | phase: :closing,
        client: client,
        caller: caller,
        monitors: [Process.monitor(caller)],
        deadline: deadline,
        permission: permission,
        timer: Process.send_after(self(), :retirement_expired, max(deadline - now(), 0))
    }

    {:reply, {:ok, permission}, next}
  end

  def handle_call({:admit, method, stage, permission}, _from, state) do
    allowed =
      case state.phase do
        :active ->
          true

        :starting ->
          now() < state.deadline and Process.alive?(state.caller) and Process.alive?(state.host)

        :closing ->
          method == :delete and permission == state.permission and
            not state.submitted and now() < state.deadline and Process.alive?(state.caller)
      end

    if allowed do
      submitted = state.submitted or (state.phase == :closing and stage == :submit)
      {:reply, :ok, %{state | submitted: submitted}}
    else
      {:reply, {:error, :session_retired}, state}
    end
  end

  @impl true
  def handle_info(:retirement_expired, %{phase: :closing} = state), do: cancel(state)

  def handle_info(:expired, %{phase: :starting} = state), do: cancel(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state.monitors, do: cancel(state), else: {:noreply, state}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  defp cancel(state) do
    if is_pid(state.client), do: Process.exit(state.client, :kill)
    Process.exit(state.integration, :kill)
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
