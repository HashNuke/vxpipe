defmodule Vxpipe.Calls.Diagnostics.Coverage do
  @moduledoc "Coverage of one selected capture window, never a claim about the entire call."
  alias Vxpipe.Calls.LatencyRun
  @termination_reasons [:disabled, :call_ended]

  def describe(run, stored_turns, now, freshness_ms \\ 5_000)
  def describe(nil, 0, %DateTime{}, _freshness_ms), do: %{status: :not_collected}

  def describe(%LatencyRun{} = run, stored_turns, %DateTime{} = now, freshness_ms)
      when is_integer(stored_turns) and stored_turns >= 0 and
             is_integer(freshness_ms) and freshness_ms in 1..60_000 do
    {termination, recorded_reasons} = Enum.split_with(run.reasons, &(&1 in @termination_reasons))
    reasons = recorded_reasons ++ loss_reasons(run, stored_turns)
    heartbeat_age = DateTime.diff(now, run.heartbeat_at, :millisecond)
    future_close? = run.closed_at != nil and DateTime.compare(run.closed_at, now) == :gt

    {status, reasons} =
      cond do
        heartbeat_age < 0 or future_close? ->
          {:unconfirmed, [:clock_uncertain | reasons]}

        run.state == :running and heartbeat_age > freshness_ms ->
          {:unconfirmed, [:stale_heartbeat | reasons]}

        reasons != [] or run.state == :incomplete ->
          {:incomplete, reasons}

        run.state == :running ->
          {:collecting, []}

        true ->
          {:complete, []}
      end

    %{
      status: status,
      recorded_state: run.state,
      reasons: Enum.uniq(reasons),
      termination_reasons: termination,
      observed_turns: run.counts.observed_turns,
      stored_turns: stored_turns,
      pending_turns: max(run.counts.observed_turns - stored_turns, 0),
      dropped_audio_frames: run.counts.dropped_audio_frames,
      unmatched_provider_events: run.counts.unmatched_provider_events
    }
  end

  defp loss_reasons(run, stored_turns) do
    []
    |> add(run.counts.dropped_audio_frames > 0, :audio_gap)
    |> add(run.counts.unmatched_provider_events > 0, :unmatched_provider_events)
    |> add(run.state != :running and stored_turns < run.counts.observed_turns, :storage_loss)
    |> add(run.state != :running and stored_turns > run.counts.observed_turns, :counter_mismatch)
  end

  defp add(reasons, true, reason), do: reasons ++ [reason]
  defp add(reasons, false, _reason), do: reasons
end
