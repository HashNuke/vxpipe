defmodule Vxpipe.Artifacts.Metadata.Publisher do
  @moduledoc false

  use GenServer

  alias Vxpipe.Artifacts.Metadata.{Configuration, Publisher.State}
  alias Vxpipe.Artifacts.Result

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    result = Keyword.fetch!(options, :result)

    %{
      id: {__MODULE__, result.manifest.artifact_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @impl true
  def init(options) do
    with %Result{} = result <- Keyword.get(options, :result),
         %Configuration{} = configuration <- Keyword.get(options, :configuration),
         {:ok, observer} <- optional_observer(Keyword.get(options, :observer)) do
      state = %State{result: result, configuration: configuration, observer: observer}
      {:ok, state, {:continue, :write}}
    else
      _invalid -> {:stop, :invalid_metadata_publication}
    end
  end

  @impl true
  def handle_continue(:write, state), do: {:noreply, start_write(state)}

  @impl true
  def handle_info({reference, outcome}, %State{task: %Task{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    state = state |> cancel_timeout() |> Map.put(:task, nil)
    outcome(outcome, state)
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, reason},
        %State{task: %Task{ref: reference}} = state
      ) do
    state = state |> cancel_timeout() |> Map.put(:task, nil)
    retry_or_finish({:metadata_writer_exit, reason}, state)
  end

  def handle_info(
        {:metadata_write_timeout, reference},
        %State{task: %Task{ref: reference}} = state
      ) do
    _result = Task.shutdown(state.task, :brutal_kill)
    state = %{state | task: nil, timeout_timer: nil}
    retry_or_finish(:metadata_writer_timeout, state)
  end

  def handle_info(:retry, state), do: {:noreply, start_write(state)}
  def handle_info(_message, state), do: {:noreply, state}

  defp start_write(state) do
    configuration = state.configuration

    task =
      Task.Supervisor.async_nolink(Vxpipe.Artifacts.MetadataTaskSupervisor, fn ->
        configuration.writer.write(configuration.writer_options, state.result)
      end)

    timeout_timer =
      Process.send_after(
        self(),
        {:metadata_write_timeout, task.ref},
        configuration.write_timeout_ms
      )

    %{state | attempt: state.attempt + 1, task: task, timeout_timer: timeout_timer}
  end

  defp outcome(:ok, state) do
    notify(state, {:vxpipe_artifact_metadata_published, self(), state.result, state.attempt})
    {:stop, :normal, state}
  end

  defp outcome({:discard, reason}, state) do
    notify(state, {:vxpipe_artifact_metadata_discarded, self(), state.result, reason})
    {:stop, :normal, state}
  end

  defp outcome({:retry, reason}, state), do: retry_or_finish(reason, state)

  defp outcome(_invalid, state) do
    notify(
      state,
      {:vxpipe_artifact_metadata_discarded, self(), state.result,
       :invalid_metadata_writer_response}
    )

    {:stop, :normal, state}
  end

  defp retry_or_finish(reason, state) do
    if state.attempt < state.configuration.maximum_attempts do
      notify(
        state,
        {:vxpipe_artifact_metadata_retrying, self(), state.result, state.attempt, reason}
      )

      _timer = Process.send_after(self(), :retry, state.configuration.retry_delay_ms)
      {:noreply, state}
    else
      notify(
        state,
        {:vxpipe_artifact_metadata_unavailable, self(), state.result, state.attempt, reason}
      )

      {:stop, :normal, state}
    end
  end

  defp cancel_timeout(%State{timeout_timer: nil} = state), do: state

  defp cancel_timeout(state) do
    _result = Process.cancel_timer(state.timeout_timer)
    %{state | timeout_timer: nil}
  end

  defp notify(%State{observer: nil}, _message), do: :ok
  defp notify(%State{observer: observer}, message), do: send(observer, message)

  defp optional_observer(nil), do: {:ok, nil}
  defp optional_observer(observer) when is_pid(observer), do: {:ok, observer}
  defp optional_observer(_observer), do: {:error, :invalid_observer}
end
