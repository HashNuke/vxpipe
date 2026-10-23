defmodule Vxpipe.Gateway.Telephony.DialSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, EndLeg, LegReference, Submission}

  @submission_timeout 35_000

  def start_link(_options), do: Task.Supervisor.start_link(name: __MODULE__)

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, type: :supervisor}
  end

  def submit(owner, service, dial) do
    submit_command(owner, :outgoing_dial_result, fn ->
      Adapter.dial(service.adapter, service.adapter_options, dial)
    end)
  end

  def end_leg(owner, service, leg_id, control_id, reason) do
    submit_command(owner, :outgoing_end_result, fn ->
      Adapter.end_leg(service.adapter, service.adapter_options, %EndLeg{
        leg: %LegReference{leg_id: leg_id, provider_call_control_id: control_id},
        reason: reason
      })
    end)
  end

  defp submit_command(owner, message, operation) when owner == self() do
    release = make_ref()

    case Task.Supervisor.start_child(__MODULE__, fn ->
           owner_monitor = Process.monitor(owner)
           await_release(owner, owner_monitor, release, message, operation)
         end) do
      {:ok, observer} ->
        monitor = Process.monitor(observer)
        send(observer, {:release, release})
        {:ok, observer, monitor}

      error ->
        error
    end
  rescue
    _exception -> {:error, :submission_unavailable}
  catch
    :exit, _reason -> {:error, :submission_unavailable}
  end

  defp submit_command(_owner, _message, _operation), do: {:error, :invalid_command_owner}

  # The caller must own its monitor before even an immediately completed request
  # can let the observer exit. A late monitor would report :noproc, losing proof.
  defp await_release(owner, owner_monitor, release, message, operation) do
    receive do
      {:release, ^release} ->
        task = Task.Supervisor.async_nolink(__MODULE__, operation)
        await_submission(owner, owner_monitor, task, message)

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        :ok
    after
      @submission_timeout -> exit(:command_start_timeout)
    end
  end

  # A separate supervised observer remains responsive while the HTTP task is blocked.
  # Owner death cancels the local request; ordinary abandonment keeps the leg alive
  # long enough to identify and hang up a late carrier acceptance.
  defp await_submission(owner, monitor, %Task{ref: reference} = task, message) do
    receive do
      {^reference, result} ->
        receive do
          {:DOWN, ^reference, :process, _pid, _reason} -> :ok
        after
          @submission_timeout -> Task.shutdown(task, :brutal_kill)
        end

        send(owner, {message, self(), result})

      {:DOWN, ^reference, :process, _pid, _reason} ->
        send(owner, {message, self(), unknown()})

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        Task.shutdown(task, :brutal_kill)
    after
      @submission_timeout ->
        Task.shutdown(task, :brutal_kill)
        send(owner, {message, self(), unknown()})
    end
  end

  defp unknown, do: {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}
end
