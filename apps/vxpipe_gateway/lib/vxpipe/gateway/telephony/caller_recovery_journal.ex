defmodule Vxpipe.Gateway.Telephony.CallerRecoveryJournal do
  @moduledoc "Exact-leg evidence retained by the original owner during a storage outage."

  @storage_budget 1_000
  @retry_ms 2_000
  @supervisor Vxpipe.Gateway.AdmissionTaskSupervisor

  defstruct [
    :backend,
    :claim,
    :deadline,
    :command,
    :reason,
    :started_ms,
    pending: [],
    recorded: MapSet.new(),
    retry: nil
  ]

  def new(backend, claim, leg_id, deadline, reason) do
    %__MODULE__{
      backend: backend,
      claim: claim,
      command: leg_id,
      deadline: deadline,
      started_ms: System.monotonic_time(:millisecond),
      reason: reason
    }
  end

  def record(journal, phase, now_ms \\ System.monotonic_time(:millisecond))
  def record(nil, _phase, _now_ms), do: nil

  def record(journal, phase, now_ms) do
    if MapSet.member?(journal.recorded, phase) or List.keymember?(journal.pending, phase, 0) do
      journal
    else
      enqueue(journal, {phase, now_ms - journal.started_ms})
    end
  end

  def retry(%{retry: token, pending: [{phase, _elapsed} = observation | rest]} = journal, token) do
    case persist(journal, observation) do
      :ok ->
        schedule(%{
          journal
          | recorded: MapSet.put(journal.recorded, phase),
            pending: rest,
            retry: nil
        })

      :unavailable ->
        schedule(%{journal | retry: nil})
    end
  end

  def retry(journal, _token), do: journal

  def settled?(nil), do: true
  def settled?(journal), do: journal.pending == []

  defp enqueue(%{pending: []} = journal, {phase, _elapsed} = observation) do
    case persist(journal, observation) do
      :ok -> %{journal | recorded: MapSet.put(journal.recorded, phase)}
      :unavailable -> schedule(%{journal | pending: [observation]})
    end
  end

  defp enqueue(journal, observation), do: %{journal | pending: journal.pending ++ [observation]}

  defp schedule(%{pending: []} = journal), do: journal

  defp schedule(journal) do
    token = make_ref()
    Process.send_after(self(), {:retry_recovery_journal, token}, @retry_ms)
    %{journal | retry: token}
  end

  def command_id(journal, phase) do
    prefix =
      cond do
        phase in [
          :announcement_requested,
          :announcement_completed,
          :announcement_failed,
          :announcement_unknown
        ] ->
          "recovery-"

        phase in [
          :transfer_announcement_requested,
          :transfer_announcement_completed,
          :transfer_announcement_failed,
          :transfer_announcement_unknown
        ] ->
          "recovery-transfer-"

        phase in [
          :transfer_requested,
          :transfer_bridged,
          :transfer_failed,
          :transfer_busy,
          :transfer_rejected,
          :transfer_unanswered,
          :transfer_unknown,
          :transfer_abandoned
        ] ->
          "peer-"

        true ->
          "hangup-"
      end

    prefix <> journal.command
  end

  defp entry(journal, phase)
       when phase in [:announcement_requested, :transfer_announcement_requested],
       do: {phase, journal.reason}

  defp entry(_journal, phase), do: phase

  defp persist(%{backend: {module, context}} = journal, {phase, elapsed_ms}) do
    task =
      Task.Supervisor.async_nolink(@supervisor, fn ->
        module.record_caller_recovery(
          context,
          journal.claim,
          {:timed, entry(journal, phase), elapsed_ms},
          command_id(journal, phase),
          journal.deadline
        )
      end)

    case Task.yield(task, @storage_budget) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} -> :ok
      _unconfirmed -> :unavailable
    end
  catch
    :exit, _reason -> :unavailable
  end
end
