defmodule Vxpipe.MCP.SessionStartup do
  @moduledoc false

  use GenServer, restart: :temporary

  def name(integration),
    do: {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:session_startup, integration}}}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :integration)))

  def ready(integration), do: GenServer.call(name(integration), :ready, 500)

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
         ready: false
       }}
    else
      {:stop, :connection_failed}
    end
  end

  @impl true
  def handle_call(:ready, _from, %{ready: true} = state), do: {:reply, :ok, state}

  def handle_call(:ready, from, state) do
    if now() < state.deadline and Process.alive?(state.caller) and Process.alive?(state.host) do
      Process.cancel_timer(state.timer)
      Enum.each(state.monitors, &Process.demonitor(&1, [:flush]))
      {:reply, :ok, %{state | ready: true, monitors: [], timer: nil}}
    else
      GenServer.reply(from, {:error, :connection_failed})
      cancel(state)
    end
  end

  @impl true
  def handle_info(:expired, %{ready: false} = state), do: cancel(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state.monitors, do: cancel(state), else: {:noreply, state}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  defp cancel(state) do
    Process.exit(state.integration, :kill)
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
