defmodule Vxpipe.Calls.LatencyReportsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{InstallationOperator, TestLatencyReadRepository, TestLatencyRecords}

  setup do
    run = %{
      TestLatencyRecords.run()
      | heartbeat_at: DateTime.add(DateTime.utc_now(), -10, :second)
    }

    {:ok, access} = Calls.operator_call_access(InstallationOperator.authority(), run.tenant_key)

    context = %{
      owner: self(),
      run: run,
      error: nil,
      summary: [%{profile: run.profile, observed_turns: 120}],
      turns: Enum.map(1..3, &%{turn_id: "turn-#{&1}", revision: &1})
    }

    %{
      access: access,
      context: context,
      options: [latency_repository: {TestLatencyReadRepository, context}]
    }
  end

  test "report pages keep full-call aggregates and expose stale coverage honestly", c do
    assert {:ok, report} = Calls.fetch_latency_report(c.access, "call-1", c.options)
    assert report.summary == c.context.summary
    assert report.next_cursor == "run-next"

    assert [%{run: run, coverage: %{status: :unconfirmed, reasons: [:stale_heartbeat]}}] =
             report.entries

    assert run.id == "run-1"
    assert_received {:list_runs, "tenant-1", "call-1", 50, nil}
    assert_received {:summarize, "tenant-1", "call-1"}
  end

  test "turn pages retain revisions and bound reads to one authorized run", c do
    options = Keyword.put(c.options, :limit, 2)
    assert {:ok, first} = Calls.fetch_latency_turns(c.access, "call-1", "run-1", options)
    assert first.entries == Enum.take(c.context.turns, 2)
    assert first.next_cursor == "turn-2"

    assert {:ok, last} =
             Calls.fetch_latency_turns(
               c.access,
               "call-1",
               "run-1",
               Keyword.put(options, :cursor, first.next_cursor)
             )

    assert last.entries == [%{turn_id: "turn-3", revision: 3}]
    assert last.next_cursor == nil
    assert_received {:list_turns, "tenant-1", "call-1", "run-1", 2, "turn-2"}
  end

  test "unauthorized input is rejected before any repository read", c do
    assert {:error, :invalid_latency_request} =
             Calls.fetch_latency_report(nil, "call-1", c.options)

    assert {:error, :invalid_latency_request} =
             Calls.fetch_latency_turns(nil, "call-1", "run-1", c.options)

    refute_received {:list_runs, _, _, _, _}
    refute_received {:fetch_run, _, _, _}
  end

  test "tenant and run ownership cannot be overridden by options", c do
    {:ok, other} = Calls.operator_call_access(InstallationOperator.authority(), "other")

    assert {:error, :call_not_found} =
             Calls.fetch_latency_report(
               other,
               "call-1",
               Keyword.put(c.options, :tenant_key, "tenant-1")
             )

    assert {:error, :call_not_found} =
             Calls.fetch_latency_turns(other, "call-1", "run-1", c.options)

    assert {:error, :latency_run_not_found} =
             Calls.fetch_latency_turns(c.access, "call-1", "foreign-run", c.options)

    refute_received {:list_turns, _, _, _, _, _}
  end

  test "malformed identifiers, limits and cursors are rejected before reads", c do
    for options <- [
          [limit: 0],
          [limit: 101],
          [limit: "50"],
          [cursor: ""],
          [cursor: String.duplicate("a", 257)],
          [cursor: 1]
        ] do
      invalid = Keyword.merge(c.options, options)

      assert {:error, :invalid_latency_request} =
               Calls.fetch_latency_report(c.access, "call-1", invalid)

      assert {:error, :invalid_latency_request} =
               Calls.fetch_latency_turns(c.access, "call-1", "run-1", invalid)
    end

    assert {:error, :invalid_latency_request} =
             Calls.fetch_latency_report(c.access, "", c.options)

    assert {:error, :invalid_latency_request} =
             Calls.fetch_latency_turns(c.access, "call-1", "", c.options)

    refute_received {:list_runs, _, _, _, _}
    refute_received {:fetch_run, _, _, _}
  end

  test "storage failure remains a diagnostic read error", c do
    options = [
      latency_repository: {TestLatencyReadRepository, %{c.context | error: :unavailable}}
    ]

    assert {:error, :unavailable} = Calls.fetch_latency_report(c.access, "call-1", options)

    assert {:error, :unavailable} =
             Calls.fetch_latency_turns(c.access, "call-1", "run-1", options)

    refute_received {:summarize, _, _}
    refute_received {:list_turns, _, _, _, _, _}
  end
end
