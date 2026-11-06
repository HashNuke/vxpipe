defmodule Vxpipe.MCP.CheckLifetime do
  @moduledoc false
  use GenServer, restart: :temporary

  def name(key), do: {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:check_lifetime, key}}}

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: name(Keyword.fetch!(options, :key)))

  def configure(key, request), do: GenServer.call(name(key), {:configure, request}, 500)
  def claim(key, role), do: GenServer.call(name(key), {:claim, role}, 10_000)
  def ready(key), do: GenServer.call(name(key), :ready, 500)
  def complete(key, result), do: GenServer.call(name(key), {:complete, result}, 500)

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    deadline = Keyword.fetch!(options, :deadline)
    Process.send_after(self(), :expired, max(deadline - now(), 0))

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       key: Keyword.fetch!(options, :key),
       deadline: deadline,
       request: nil,
       client: nil,
       worker: nil,
       client_ref: nil,
       worker_ref: nil,
       waiting: %{},
       ready: false,
       closing: false,
       result: nil
     }}
  end

  @impl true
  def handle_call(_request, _from, %{closing: true} = state),
    do: {:reply, {:error, :expired}, state}

  def handle_call(request, from, state) do
    if now() >= state.deadline do
      GenServer.reply(from, {:error, :expired})
      close(state, {:error, :mcp_connection_failed})
    else
      accept(request, from, state)
    end
  end

  defp accept({:configure, request}, {owner, _} = from, %{owner: owner, request: nil} = state) do
    GenServer.reply(from, :ok)
    {:noreply, release_waiters(%{state | request: request})}
  end

  defp accept({:claim, role}, {pid, _} = from, state) when role in [:client, :worker] do
    if Map.fetch!(state, role) == nil do
      reference = if role == :client, do: :client_ref, else: :worker_ref
      state = state |> Map.put(role, pid) |> Map.put(reference, Process.monitor(pid))
      {:noreply, release_waiters(%{state | waiting: Map.put(state.waiting, role, from)})}
    else
      {:reply, {:error, :already_claimed}, state}
    end
  end

  defp accept(:ready, {client, _}, %{client: client} = state),
    do: {:reply, :ok, release_waiters(%{state | ready: true})}

  defp accept({:complete, result}, {worker, _} = from, %{worker: worker} = state) do
    GenServer.reply(from, :ok)
    close(state, result)
  end

  defp accept(_request, _from, state), do: {:reply, {:error, :invalid_request}, state}

  @impl true
  def handle_info(:expired, state), do: close(state, {:error, :mcp_connection_failed})

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{client_ref: ref, closing: true} = state
      ),
      do: finish(%{state | client: nil})

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    cond do
      ref == state.client_ref ->
        close(%{state | client: nil}, {:error, :mcp_connection_failed})

      ref == state.owner_ref ->
        close(state, {:error, :mcp_connection_failed})

      ref == state.worker_ref and not state.closing ->
        close(state, {:error, :mcp_connection_failed})

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def format_status(status), do: Map.new(status, fn {key, _value} -> {key, :redacted} end)

  defp release_waiters(%{request: nil} = state), do: state

  defp release_waiters(state) do
    state = release(state, :client, state.request)

    if state.ready,
      do: release(state, :worker, Map.drop(state.request, [:client_options])),
      else: state
  end

  defp release(state, role, request) do
    case Map.pop(state.waiting, role) do
      {nil, _waiting} ->
        state

      {from, waiting} ->
        GenServer.reply(from, {:ok, request})
        %{state | waiting: waiting}
    end
  end

  defp close(state, result) do
    state = %{state | closing: true, result: result, request: nil, waiting: %{}}

    if state.client do
      Process.exit(state.client, :kill)
      {:noreply, state}
    else
      finish(state)
    end
  end

  defp finish(state) do
    send(state.owner, {:mcp_check_result, state.key, state.result})
    {:stop, :normal, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
