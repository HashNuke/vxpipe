defmodule Vxpipe.Persistence.LatencySummaryQuery do
  @moduledoc false

  # Values are constructor-derived nullable durations; grouping by the complete
  # bounded profile prevents combining different model/algorithm cohorts.
  def fetch(repo, call_id) do
    result =
      repo.query!(
        """
        SELECT r.profile, metric.key, count(metric.value),
          count(*) - count(metric.value),
          percentile_cont(0.5) WITHIN GROUP (ORDER BY metric.value::bigint),
          percentile_cont(0.95) WITHIN GROUP (ORDER BY metric.value::bigint)
        FROM call_latency_runs r
        JOIN call_turn_diagnostics t ON t.run_id = r.id
        CROSS JOIN LATERAL jsonb_each_text(t.durations_us) metric
        WHERE r.call_id = $1
        GROUP BY r.profile, metric.key
        ORDER BY r.profile, metric.key
        """,
        [call_id]
      )

    groups =
      Enum.map(result.rows, fn [profile, metric, valid, excluded, p50, p95] ->
        %{
          profile: profile,
          metric: metric,
          valid_count: valid,
          excluded_count: excluded,
          p50_us: p50,
          p95_us: p95
        }
      end)

    {:ok, groups}
  end
end
