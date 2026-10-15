defmodule Vxpipe.Gateway.Telephony.IncomingSubmission do
  @moduledoc false

  @supervisor Vxpipe.Gateway.AdmissionTaskSupervisor
  @timeout 35_000

  def start(owner, kind, operation) when owner == self() do
    case Task.Supervisor.start_child(@supervisor, fn ->
           wait_for_start(owner, kind, operation)
         end) do
      {:ok, worker} ->
        monitor = Process.monitor(worker)
        send(worker, :begin_submission)
        {:ok, worker, monitor}

      error ->
        error
    end
  end

  # Install the owner's observer monitor before any operation can complete.
  defp wait_for_start(owner, kind, operation) do
    monitor = Process.monitor(owner)

    receive do
      :begin_submission ->
        task = Task.Supervisor.async_nolink(@supervisor, operation)
        await(owner, monitor, kind, task)

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        :ok
    after
      @timeout -> :ok
    end
  end

  # Monitor the owner independently of the bounded carrier HTTP request. A local
  # timeout is an unknown carrier outcome, never evidence that its leg ended.
  defp await(owner, monitor, kind, %Task{ref: reference} = task) do
    receive do
      {^reference, result} ->
        receive do
          {:DOWN, ^reference, :process, _pid, _reason} -> :ok
        after
          @timeout -> Task.shutdown(task, :brutal_kill)
        end

        send(owner, {:incoming_submission, kind, self(), result})

      {:DOWN, ^reference, :process, _pid, _reason} ->
        send(owner, {:incoming_submission, kind, self(), {:error, :submission_unknown}})

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        Task.shutdown(task, :brutal_kill)
    after
      @timeout ->
        Task.shutdown(task, :brutal_kill)
        send(owner, {:incoming_submission, kind, self(), {:error, :submission_unknown}})
    end
  end
end
