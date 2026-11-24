defmodule Vxpipe.Gateway.Telephony.CallerRecoveryJournalTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.CallerRecoveryJournal, as: Journal

  test "a lost storage acknowledgement retries the exact evidence at every carrier phase" do
    writes = start_supervised!({Agent, fn -> %{} end})
    claim = %{tenant: "tenant", call: "call", incarnation: "incarnation"}
    deadline = ~U[2026-11-24 12:00:00Z]

    journal =
      Journal.new({__MODULE__, writes}, claim, "inbound-leg", deadline, :media_process_lost)

    phases = %{
      "recovery-inbound-leg" =>
        ~w(announcement_requested announcement_completed announcement_failed announcement_unknown)a,
      "recovery-transfer-inbound-leg" =>
        ~w(transfer_announcement_requested transfer_announcement_completed transfer_announcement_failed transfer_announcement_unknown)a,
      "peer-inbound-leg" =>
        ~w(transfer_requested transfer_bridged transfer_failed transfer_busy transfer_rejected transfer_unanswered transfer_unknown transfer_abandoned)a,
      "hangup-inbound-leg" => ~w(hangup_requested carrier_ended carrier_unknown)a
    }

    for {command, group} <- phases, phase <- group do
      pending = Journal.record(journal, phase, journal.started_ms + 42)
      refute Journal.settled?(pending)
      assert Journal.record(pending, phase) == pending
      assert Journal.retry(pending, make_ref()) == pending

      settled = Journal.retry(pending, pending.retry)
      assert Journal.settled?(settled)
      assert Journal.retry(settled, pending.retry) == settled
      assert Journal.record(settled, phase) == settled

      entry =
        if phase in [:announcement_requested, :transfer_announcement_requested],
          do: {phase, :media_process_lost},
          else: phase

      assert Agent.get(writes, &Map.fetch!(&1, {:timed, entry, 42})) ==
               List.duplicate({claim, command, deadline}, 2)
    end
  end

  test "a later phase keeps its observed offset while an earlier write is pending" do
    writes = start_supervised!({Agent, fn -> %{} end})
    deadline = ~U[2026-11-24 12:00:00Z]
    journal = Journal.new({__MODULE__, writes}, :claim, "leg", deadline, :media_process_lost)
    origin = journal.started_ms

    queued =
      journal
      |> Journal.record(:hangup_requested, origin + 15)
      |> Journal.record(:carrier_ended, origin + 180)
      |> Journal.record(:carrier_ended, origin + 600)

    terminal = {:timed, :carrier_ended, 180}
    refute Agent.get(writes, &Map.has_key?(&1, terminal))

    drained =
      Enum.reduce(1..3, queued, fn _, pending -> Journal.retry(pending, pending.retry) end)

    assert Journal.settled?(drained)

    assert Agent.get(writes, &Map.fetch!(&1, terminal)) ==
             List.duplicate({:claim, "hangup-leg", deadline}, 2)
  end

  # Simulate a committed write whose acknowledgement was lost.
  def record_caller_recovery(writes, claim, phase, command, deadline) do
    Agent.get_and_update(writes, fn history ->
      previous = Map.get(history, phase, [])
      result = if previous == [], do: {:error, :acknowledgement_lost}, else: :ok
      {result, Map.put(history, phase, [{claim, command, deadline} | previous])}
    end)
  end
end
