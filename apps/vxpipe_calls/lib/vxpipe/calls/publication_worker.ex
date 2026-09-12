defmodule Vxpipe.Calls.PublicationWorker do
  @moduledoc "Short-lived supervised delivery worker for one immutable call-details snapshot."

  use GenServer

  alias Vxpipe.Calls.{CallDetailsPublication, PublicationAttempt, PublicationJob}
  alias Vxpipe.Calls.PublicationWorker.State

  @spec start_link(PublicationJob.t()) :: GenServer.on_start()
  def start_link(%PublicationJob{} = job) do
    GenServer.start_link(__MODULE__, job, name: PublicationJob.via(job))
  end

  @spec child_spec(PublicationJob.t()) :: Supervisor.child_spec()
  def child_spec(%PublicationJob{} = job) do
    %{
      id: {__MODULE__, PublicationJob.key(job)},
      start: {__MODULE__, :start_link, [job]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  @impl true
  def init(%PublicationJob{} = job), do: {:ok, %State{job: job}, {:continue, :attempt}}

  @impl true
  def handle_continue(:attempt, state), do: {:noreply, start_attempt(state)}

  @impl true
  def handle_info({reference, outcome}, %State{task: %Task{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    state = state |> cancel_timeout() |> Map.put(:task, nil)
    settle(outcome, state)
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, reason},
        %State{task: %Task{ref: reference}} = state
      ) do
    state = state |> cancel_timeout() |> Map.put(:task, nil)
    retry_or_finish({:publication_attempt_exit, reason}, state)
  end

  def handle_info(
        {:publication_attempt_timeout, reference},
        %State{task: %Task{ref: reference}} = state
      ) do
    _result = Task.shutdown(state.task, :brutal_kill)
    state = %{state | task: nil, timeout_timer: nil}
    retry_or_finish(:publication_attempt_timeout, state)
  end

  def handle_info(:retry, %State{task: nil} = state), do: {:noreply, start_attempt(state)}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{task: nil}), do: :ok
  def terminate(_reason, %State{task: task}), do: Task.shutdown(task, :brutal_kill)

  defp start_attempt(state) do
    task =
      Task.Supervisor.async_nolink(state.job.task_supervisor, fn ->
        PublicationAttempt.run(state.job)
      end)

    timeout_timer =
      Process.send_after(
        self(),
        {:publication_attempt_timeout, task.ref},
        state.job.attempt_timeout_ms
      )

    %{state | attempt: state.attempt + 1, task: task, timeout_timer: timeout_timer}
  end

  defp settle({:ok, %CallDetailsPublication{} = publication, disposition}, state)
       when disposition in [:published, :already_published] do
    notify(state, {:vxpipe_call_details_published, self(), publication.id, state.attempt})
    {:stop, :normal, state}
  end

  defp settle({:error, reason}, state), do: retry_or_finish(reason, state)
  defp settle(_invalid, state), do: retry_or_finish(:invalid_publication_attempt_response, state)

  defp retry_or_finish(reason, state) do
    if state.attempt < state.job.maximum_attempts do
      notify(
        state,
        {:vxpipe_call_details_retrying, self(), state.job.snapshot.publication_id, state.attempt,
         reason}
      )

      _timer = Process.send_after(self(), :retry, state.job.retry_delay_ms)
      {:noreply, state}
    else
      notify(
        state,
        {:vxpipe_call_details_unavailable, self(), state.job.snapshot.publication_id,
         state.attempt, reason}
      )

      {:stop, :normal, state}
    end
  end

  defp cancel_timeout(%State{timeout_timer: nil} = state), do: state

  defp cancel_timeout(state) do
    _result = Process.cancel_timer(state.timeout_timer)
    %{state | timeout_timer: nil}
  end

  defp notify(%State{job: %PublicationJob{observer: nil}}, _message), do: :ok

  defp notify(%State{job: %PublicationJob{observer: observer}}, message),
    do: send(observer, message)
end
