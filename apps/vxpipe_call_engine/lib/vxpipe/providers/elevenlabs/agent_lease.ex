defmodule Vxpipe.Providers.ElevenLabs.AgentLease do
  @moduledoc "Owns asynchronous preparation and checked deletion across a session owner's death."
  use GenServer

  alias Vxpipe.Providers.ElevenLabs.{AgentAPI, AgentLeaseRequest}

  @derive {Inspect, only: [:phase]}
  defstruct [
    :owner,
    :owner_monitor,
    :supervisor,
    :worker,
    :worker_monitor,
    :client,
    :definition,
    :api_module,
    :lifetime_ms,
    phase: :preparing
  ]

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc "Acknowledge retirement promptly; checked cleanup is a separate terminal message."
  def release(lease) do
    GenServer.call(lease, :release, 1_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    api = Keyword.get(options, :api_module, AgentAPI)
    lifetime_ms = Keyword.get(options, :lifetime_ms, 3_600_000)

    if is_pid(owner) and is_atom(api) and Code.ensure_loaded?(api) and
         function_exported?(api, :with_agent, 3) and is_integer(lifetime_ms) and
         lifetime_ms in 1..3_600_000 do
      {:ok,
       %__MODULE__{
         owner: owner,
         owner_monitor: Process.monitor(owner),
         supervisor: Keyword.fetch!(options, :supervisor),
         client: Keyword.fetch!(options, :client),
         definition: Keyword.fetch!(options, :definition),
         api_module: api,
         lifetime_ms: lifetime_ms
       }, {:continue, :prepare}}
    else
      {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_continue(:prepare, state) do
    options = [
      lease: self(),
      supervisor: GenServer.whereis(state.supervisor),
      client: state.client,
      definition: state.definition,
      api_module: state.api_module,
      lifetime_ms: state.lifetime_ms
    ]

    case DynamicSupervisor.start_child(state.supervisor, {AgentLeaseRequest, options}) do
      {:ok, worker} ->
        {:noreply,
         %{
           state
           | worker: worker,
             worker_monitor: Process.monitor(worker),
             client: nil,
             definition: nil
         }}

      _failure ->
        finish(state, {:error, :preparation_failed})
    end
  end

  @impl true
  def handle_call(:release, {owner, _tag}, %{owner: owner} = state) do
    state = retire(state, :released)
    {:reply, :ok, state}
  end

  def handle_call(:release, _from, state), do: {:reply, {:error, :not_owner}, state}

  @impl true
  def handle_info(
        {:elevenlabs_agent_prepared, worker, connection},
        %{worker: worker, phase: :preparing} = state
      ) do
    notify(state, {:ready, connection})
    {:noreply, %{state | phase: :ready}}
  end

  def handle_info({:elevenlabs_agent_prepared, worker, _connection}, %{worker: worker} = state),
    do: {:noreply, state}

  def handle_info(
        {:elevenlabs_agent_request_finished, worker, result},
        %{worker: worker} = state
      ) do
    Process.demonitor(state.worker_monitor, [:flush])
    finish(state, public_result(result))
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{owner_monitor: monitor, owner: owner} = state
      ),
      do: {:noreply, retire(state, :owner_lost)}

  def handle_info(
        {:DOWN, monitor, :process, worker, _reason},
        %{worker_monitor: monitor, worker: worker} = state
      ),
      do: finish(state, {:error, :request_failed})

  def handle_info(_stale_or_untrusted, state), do: {:noreply, state}

  defp retire(%{phase: :closing} = state, _reason), do: state

  defp retire(state, reason) do
    send(state.worker, {:elevenlabs_agent_release, self(), reason})
    %{state | phase: :closing}
  end

  defp public_result(reason) when reason in [:released, :owner_lost], do: reason
  defp public_result(:lease_expired), do: {:error, :lease_expired}
  defp public_result(:cleanup_failed), do: {:error, :cleanup_failed}
  defp public_result(_failure), do: {:error, :preparation_failed}

  defp finish(state, result) do
    notify(state, {:finished, result})
    {:stop, :normal, state}
  end

  defp notify(state, event),
    do: send(state.owner, {:vxpipe_elevenlabs_agent_lease, self(), event})
end
