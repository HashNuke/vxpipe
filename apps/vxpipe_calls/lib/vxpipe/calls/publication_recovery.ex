defmodule Vxpipe.Calls.PublicationRecovery do
  @moduledoc "Periodically resubmits durable pending call-details revisions to delivery workers."

  use GenServer

  alias Vxpipe.Calls.{CallDetailsPublications, PublicationWorkers}
  alias Vxpipe.Calls.PublicationRecovery.State

  @default_batch_size 100
  @default_scan_interval_ms 30_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) when is_list(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]},
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec scan(GenServer.server(), timeout()) :: {:ok, map()} | {:error, term()}
  def scan(server \\ __MODULE__, timeout \\ 5_000), do: GenServer.call(server, :scan, timeout)

  @impl true
  def init(options) do
    with batch_size when is_integer(batch_size) and batch_size > 0 <-
           Keyword.get(options, :batch_size, @default_batch_size),
         scan_interval_ms when is_integer(scan_interval_ms) and scan_interval_ms > 0 <-
           Keyword.get(options, :scan_interval_ms, @default_scan_interval_ms),
         scan_on_start when is_boolean(scan_on_start) <-
           Keyword.get(options, :scan_on_start, true),
         {:ok, observer} <- optional_observer(Keyword.get(options, :observer)) do
      state = %State{
        options: options,
        batch_size: batch_size,
        scan_interval_ms: scan_interval_ms,
        observer: observer
      }

      if scan_on_start,
        do: {:ok, state, {:continue, :scan}},
        else: {:ok, schedule(state)}
    else
      _invalid -> {:stop, :invalid_publication_recovery}
    end
  end

  @impl true
  def handle_continue(:scan, state) do
    {_result, state} = run_scan(state)
    {:noreply, schedule(state)}
  end

  @impl true
  def handle_call(:scan, _from, state) do
    {result, state} = run_scan(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:scan, state) do
    {_result, state} = run_scan(%{state | scan_timer: nil})
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_scan(state) do
    result =
      case CallDetailsPublications.list_pending(state.batch_size, state.options) do
        {:ok, publications} when is_list(publications) -> resume(publications, state.options)
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_pending_publications_response}
      end

    notify(state, {:vxpipe_call_details_recovery_scan, self(), result})
    {result, state}
  end

  defp resume(publications, options) do
    report = %{found: length(publications), started: 0, existing: 0, unavailable: 0}

    report =
      Enum.reduce(publications, report, fn publication, report ->
        case PublicationWorkers.resume(publication, options) do
          {:ok, _worker, :started} -> Map.update!(report, :started, &(&1 + 1))
          {:ok, _worker, :existing} -> Map.update!(report, :existing, &(&1 + 1))
          {:error, _reason} -> Map.update!(report, :unavailable, &(&1 + 1))
        end
      end)

    {:ok, report}
  end

  defp schedule(%State{scan_timer: nil} = state) do
    timer = Process.send_after(self(), :scan, state.scan_interval_ms)
    %{state | scan_timer: timer}
  end

  defp schedule(state), do: state

  defp optional_observer(nil), do: {:ok, nil}
  defp optional_observer(observer) when is_pid(observer), do: {:ok, observer}
  defp optional_observer(_observer), do: {:error, :observer}

  defp notify(%State{observer: nil}, _message), do: :ok
  defp notify(%State{observer: observer}, message), do: send(observer, message)
end
