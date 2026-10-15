defmodule Vxpipe.Gateway.Telephony.IncomingSubmission do
  @moduledoc false

  @supervisor Vxpipe.Gateway.AdmissionTaskSupervisor
  @timeout 35_000

  def start(owner, kind, operation) do
    Task.Supervisor.start_child(@supervisor, fn ->
      monitor = Process.monitor(owner)
      task = Task.Supervisor.async_nolink(@supervisor, operation)
      await(owner, monitor, kind, task)
    end)
  end

  # Monitor the owner independently of the bounded carrier HTTP request. A local
  # timeout is an unknown carrier outcome, never evidence that its leg ended.
  defp await(owner, monitor, kind, %Task{ref: reference} = task) do
    receive do
      {^reference, result} ->
        Process.demonitor(reference, [:flush])
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
