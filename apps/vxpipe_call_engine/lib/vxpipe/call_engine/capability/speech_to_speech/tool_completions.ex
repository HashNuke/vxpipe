defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ToolCompletions do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Tool.InvocationRegistry

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)

    {:ok,
     %{
       owner: owner,
       monitor: Process.monitor(owner),
       registry: Keyword.fetch!(options, :registry),
       consumer: Keyword.fetch!(options, :activation_id),
       leases: %{}
     }}
  end

  # Private engine handoff only. Reading a lease is not completion acceptance.
  # The coordinated model-continuation seam will own commit/release operations.
  @impl true
  def handle_call(:leases, _from, state), do: {:reply, Map.values(state.leases), state}

  @impl true
  def handle_info({:vxpipe_tool_completion_available, registry, _id}, state) do
    if registry == GenServer.whereis(state.registry) do
      case InvocationRegistry.lease_next(registry, state.consumer) do
        {:ok, lease} ->
          send(state.owner, {:vxpipe_sts_tool_completion, self(), lease})
          {:noreply, %{state | leases: Map.put(state.leases, lease.invocation_id, lease)}}

        {:error, :empty} ->
          {:noreply, state}

        {:error, :unavailable} ->
          {:stop, :normal, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :sts_tool_completions)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
