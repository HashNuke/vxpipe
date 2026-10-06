defmodule Vxpipe.Gateway.Telephony.DialSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Submission}

  @submission_timeout 35_000

  def start_link(_options), do: Task.Supervisor.start_link(name: __MODULE__)

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, type: :supervisor}
  end

  def submit(owner, service, dial) do
    Task.Supervisor.start_child(__MODULE__, fn ->
      monitor = Process.monitor(owner)

      task =
        Task.Supervisor.async_nolink(__MODULE__, fn ->
          Adapter.dial(service.adapter, service.adapter_options, dial)
        end)

      await_submission(owner, monitor, task)
    end)
  end

  # A separate supervised observer remains responsive while the HTTP task is blocked.
  # Owner death cancels the local request; ordinary abandonment keeps the leg alive
  # long enough to identify and hang up a late carrier acceptance.
  defp await_submission(owner, monitor, %Task{ref: reference} = task) do
    receive do
      {^reference, result} ->
        Process.demonitor(reference, [:flush])
        send(owner, {:outgoing_dial_result, self(), result})

      {:DOWN, ^reference, :process, _pid, _reason} ->
        send(owner, {:outgoing_dial_result, self(), unknown()})

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        Task.shutdown(task, :brutal_kill)
    after
      @submission_timeout ->
        Task.shutdown(task, :brutal_kill)
        send(owner, {:outgoing_dial_result, self(), unknown()})
    end
  end

  defp unknown, do: {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}
end
