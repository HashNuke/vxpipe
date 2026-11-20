defmodule Vxpipe.Console.CallLatencyPresenter do
  @moduledoc "Versioned diagnostic JSON with explicit provenance and microsecond units."
  @run_fields [
    :id,
    :revision,
    :settings_revision,
    :schema_version,
    :participant_id,
    :connection_id,
    :source_epoch,
    :clock_id,
    :profile,
    :state,
    :counts,
    :unattached_segments,
    :reasons
  ]
  @turn_fields [
    :run_id,
    :turn_id,
    :revision,
    :stt_allocation_id,
    :clock_id,
    :source_epoch,
    :provider_turn_id,
    :response_turn_id,
    :landmarks_us,
    :durations_us,
    :metric_reasons,
    :quality,
    :acoustic_reason,
    :acoustic_sample,
    :uncertainty_us,
    :acoustic_segments,
    :barge_in
  ]
  @summary_fields [:profile, :metric, :valid_count, :excluded_count, :p50_us, :p95_us]

  def report(report) do
    %{
      schema_version: 1,
      runs: Enum.map(report.entries, &run/1),
      summary: Enum.map(report.summary, &Map.take(&1, @summary_fields)),
      next_cursor: report.next_cursor
    }
  end

  def turns(run_id, page) do
    %{
      schema_version: 1,
      run_id: run_id,
      turns: Enum.map(page.entries, &Map.take(&1, @turn_fields)),
      next_cursor: page.next_cursor
    }
  end

  defp run(%{run: run, coverage: coverage}) do
    run
    |> Map.take(@run_fields)
    |> Map.merge(%{
      anchor_utc: timestamp(run.anchor_utc),
      heartbeat_at: timestamp(run.heartbeat_at),
      closed_at: timestamp(run.closed_at),
      coverage: coverage
    })
  end

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
