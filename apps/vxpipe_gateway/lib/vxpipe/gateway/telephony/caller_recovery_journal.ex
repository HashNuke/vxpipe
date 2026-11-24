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
    pending: [],
    recorded: MapSet.new(),
    retry: nil
  ]

  def new(backend, claim, leg_id, deadline) do
    %__MODULE__{backend: backend, claim: claim, command: leg_id, deadline: deadline}
  end

  def record(nil, _phase), do: nil

  def record(journal, phase) do
    if MapSet.member?(journal.recorded, phase) or phase in journal.pending do
      journal
    else
      enqueue(journal, phase)
    end
  end

  def retry(%{retry: token, pending: [phase | rest]} = journal, token) do
    case persist(journal, phase) do
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

  defp enqueue(%{pending: []} = journal, phase) do
    case persist(journal, phase) do
      :ok -> %{journal | recorded: MapSet.put(journal.recorded, phase)}
      :unavailable -> schedule(%{journal | pending: [phase]})
    end
  end

  defp enqueue(journal, phase), do: %{journal | pending: journal.pending ++ [phase]}

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

  defp persist(%{backend: {module, context}} = journal, phase) do
    task =
      Task.Supervisor.async_nolink(@supervisor, fn ->
        module.record_caller_recovery(
          context,
          journal.claim,
          phase,
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
