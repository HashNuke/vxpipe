defmodule Vxpipe.Calls.ArchivesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallFact, Principal, TestArchiveRepository, VariableSnapshot}

  test "stores private call facts and authorizes ordered tenant-scoped reads" do
    repository = start_supervised!(TestArchiveRepository)
    options = [archive_repository: TestArchiveRepository.repository(repository)]

    assert {:ok, fact} =
             CallFact.new(
               id: "event-1",
               kind: :accepted_input,
               sequence: 3,
               tenant_key: "AAAAAAAAAAAAAAAA",
               call_id: "44444444-4444-4444-8444-444444444444",
               room_id: "55555555-5555-4555-8555-555555555555",
               incarnation_id: "rinc_archive-test",
               participant_id: "participant-1",
               activation_id: nil,
               source_participant_id: nil,
               connection_id: "connection-1",
               command_id: "command-1",
               correlation_id: "turn-1",
               tool_call_id: nil,
               public_sequence: nil,
               occurred_at: ~U[2026-09-09 11:41:00.000000Z],
               source_policy: %{revision: 0, authorization: "Bearer policy-secret"},
               payload: %{
                 content: "private transcript",
                 modality: :text,
                 provider: %{authorization: "Bearer tool-secret", safe: "retained"}
               }
             )

    refute inspect(fact) =~ "private transcript"

    assert fact.payload == %{
             "content" => "private transcript",
             "modality" => "text",
             "provider" => %{"safe" => "retained"}
           }

    assert fact.source_policy == %{"revision" => 0}

    assert {:ok, ^fact} = Calls.archive_call_fact(fact, options)

    principal = %Principal{
      tenant_key: fact.tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }

    assert {:ok, [^fact]} = Calls.fetch_call_facts(principal, fact.call_id, options)

    unauthorized = %{principal | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Calls.fetch_call_facts(unauthorized, fact.call_id, options)

    assert TestArchiveRepository.operations(repository) == [
             {:store_fact, fact.id},
             {:fetch_facts, fact.tenant_key, fact.call_id}
           ]
  end

  test "stores private snapshots and authorizes tenant-scoped reads" do
    repository = start_supervised!(TestArchiveRepository)
    options = [archive_repository: TestArchiveRepository.repository(repository)]
    snapshot = baseline_snapshot()

    assert {:ok, ^snapshot} = Calls.archive_variable_snapshot(snapshot, options)

    principal = %Principal{
      tenant_key: snapshot.tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }

    assert {:ok, history} = Calls.fetch_variable_snapshots(principal, snapshot.call_id, options)
    assert history.snapshots == [snapshot]
    assert history.latest == snapshot

    unauthorized = %{principal | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Calls.fetch_variable_snapshots(unauthorized, snapshot.call_id, options)

    assert TestArchiveRepository.operations(repository) == [
             {:store, snapshot.id},
             {:fetch, snapshot.tenant_key, snapshot.call_id}
           ]
  end

  test "projects transcript, tool history, and variable snapshots for one call" do
    repository = start_supervised!(TestArchiveRepository)
    options = [archive_repository: TestArchiveRepository.repository(repository)]
    snapshot = baseline_snapshot()

    input = call_fact(:accepted_input, 1, %{"content" => "Hello", "modality" => "text"})
    tool = call_fact(:tool_call_completed, 2, %{"name" => "lookup", "result" => %{}})
    output = call_fact(:agent_output_generated, 3, %{"text" => "Hello back."})

    assert {:ok, ^snapshot} = Calls.archive_variable_snapshot(snapshot, options)
    assert {:ok, ^tool} = Calls.archive_call_fact(tool, options)
    assert {:ok, ^output} = Calls.archive_call_fact(output, options)
    assert {:ok, ^input} = Calls.archive_call_fact(input, options)

    principal = %Principal{
      tenant_key: snapshot.tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }

    assert {:ok, history} = Calls.fetch_call_history(principal, snapshot.call_id, options)

    assert Enum.map(history.facts, & &1.kind) == [
             :accepted_input,
             :tool_call_completed,
             :agent_output_generated
           ]

    assert Enum.map(history.transcript, & &1.kind) == [:accepted_input, :agent_output_generated]
    assert history.tool_history == [tool]
    assert history.variable_snapshots.snapshots == [snapshot]
    assert history.variable_snapshots.latest == snapshot
    assert history.archive_status.state == :unconfirmed
    refute history.archive_status.complete?
    assert history.archive_status.last_sequence == 3
    assert history.archive_status.missing_sequence_count == 0
  end

  test "correlates persisted tool and variable activity without inventing timing" do
    snapshot_history = %Vxpipe.Calls.VariableSnapshotHistory{
      snapshots: [attributed_snapshot()],
      latest: attributed_snapshot()
    }

    started =
      attributed_fact(
        :tool_call_started,
        1,
        ~U[2026-09-09 11:41:01.000000Z],
        %{"arguments" => %{"order_id" => "order-7"}, "name" => "lookup_order"}
      )

    completed =
      attributed_fact(
        :tool_call_completed,
        2,
        ~U[2026-09-09 11:41:04.250000Z],
        %{"name" => "lookup_order", "result" => %{"status" => "ready"}}
      )

    history = Vxpipe.Calls.CallHistory.new([started, completed], snapshot_history)

    assert [tool_started, variables_updated, tool_completed] = history.timeline

    assert %{
             id: "attributed-event-1",
             kind: :tool_call_started,
             source: :persisted,
             source_sequence: 1,
             participant_id: "assistant-1",
             activation_id: "activation-1",
             correlation_id: "turn-1",
             tool_call_id: "tool-1",
             observed_duration_ms: nil
           } = tool_started

    assert %{
             id: "snapshot-1",
             kind: :variable_snapshot,
             source: :persisted,
             source_sequence: nil,
             participant_id: "assistant-1",
             activation_id: "activation-1",
             correlation_id: "turn-1",
             tool_call_id: "tool-1",
             variable_revision: 1,
             section_revision: 1,
             observed_duration_ms: nil
           } = variables_updated

    assert variables_updated.payload == attributed_snapshot().sections

    assert %{
             id: "attributed-event-2",
             kind: :tool_call_completed,
             source: :persisted,
             source_sequence: 2,
             participant_id: "assistant-1",
             activation_id: "activation-1",
             correlation_id: "turn-1",
             tool_call_id: "tool-1",
             observed_duration_ms: 3_250,
             duration_basis: :source_timestamps
           } = tool_completed

    incomplete = Vxpipe.Calls.CallHistory.new([completed], snapshot_history)
    assert List.last(incomplete.timeline).observed_duration_ms == nil
    assert List.last(incomplete.timeline).duration_basis == nil
    refute inspect(history) =~ "order-7"
  end

  test "reports complete and known-incomplete archive streams without inventing history" do
    snapshot_history = %Vxpipe.Calls.VariableSnapshotHistory{snapshots: [], latest: nil}
    input = call_fact(:accepted_input, 1, %{"content" => "Hello", "modality" => "text"})

    complete_closure =
      call_fact(:archive_stream_closed, 2, %{
        "discarded" => 0,
        "incomplete" => false,
        "overflow" => 0,
        "unavailable" => 0
      })

    complete_history = Vxpipe.Calls.CallHistory.new([input, complete_closure], snapshot_history)

    assert complete_history.archive_status.state == :complete
    assert complete_history.archive_status.complete?
    assert complete_history.archive_status.last_sequence == 2
    assert complete_history.archive_status.missing_sequence_count == 0
    assert complete_history.archive_status.missing_sequences == []

    incomplete_closure =
      call_fact(:archive_stream_closed, 4, %{
        "discarded" => 0,
        "incomplete" => true,
        "overflow" => 1,
        "unavailable" => 0
      })

    incomplete_history =
      Vxpipe.Calls.CallHistory.new([input, incomplete_closure], snapshot_history)

    assert incomplete_history.archive_status.state == :incomplete
    refute incomplete_history.archive_status.complete?
    assert incomplete_history.archive_status.last_sequence == 4
    assert incomplete_history.archive_status.missing_sequence_count == 2
    assert incomplete_history.archive_status.missing_sequences == [2, 3]
  end

  test "reports duplicate archive provenance explicitly" do
    first = call_fact(:accepted_input, 1, %{"content" => "Hello", "modality" => "text"})
    duplicate_id = %{first | sequence: 2}
    duplicate_sequence = %{first | id: "another-event"}

    status = Vxpipe.Calls.ArchiveStatus.from_facts([first, duplicate_id, duplicate_sequence])

    assert status.duplicate_id_count == 1
    assert status.duplicate_ids == [first.id]
    assert status.duplicate_sequence_count == 1
    assert status.duplicate_sequences == [1]
    assert status.state == :unconfirmed
  end

  test "omits policy-redacted text facts from the transcript projection" do
    snapshot_history = %Vxpipe.Calls.VariableSnapshotHistory{snapshots: [], latest: nil}

    redacted =
      call_fact(
        :accepted_input,
        1,
        %{"content" => "must-not-be-persisted", "modality" => "text"},
        source_policy: %{"revision" => 1, "save_transcripts" => false}
      )

    history = Vxpipe.Calls.CallHistory.new([redacted], snapshot_history)

    assert redacted.payload == %{"modality" => "text"}
    assert history.facts == [redacted]
    assert history.transcript == []
  end

  test "enforces baseline and update attribution without exposing private sections in inspect" do
    baseline = baseline_snapshot()
    refute inspect(baseline) =~ "private-value"

    baseline_attributes = attributes(:baseline, 0)

    assert {:error, :invalid_variable_snapshot} =
             VariableSnapshot.new(
               Keyword.put(baseline_attributes, :command_id, "baseline-cannot-have-a-command")
             )

    assert {:error, :invalid_variable_snapshot} =
             VariableSnapshot.new(attributes(:update, 1))

    assert {:ok, update} =
             attributes(:update, 1)
             |> Keyword.merge(
               command_id: "command-1",
               participant_id: "participant-1",
               activation_id: "activation-1",
               source_participant_id: "source-1",
               correlation_id: "correlation-1",
               tool_call_id: "tool-1",
               section: "private",
               section_revision: 1
             )
             |> VariableSnapshot.new()

    assert update.kind == :update
  end

  test "canonicalizes archival JSON maps before assigning an immutable identity" do
    attributes =
      attributes(:baseline, 0)
      |> Keyword.put(:sections, %{
        "private" => %{revision: 0, value: %{nested: %{enabled: true}}}
      })
      |> Keyword.put(:source_policy, %{
        revision: 0,
        save_transcripts: true,
        authorization: "Bearer policy-secret"
      })

    assert {:ok, snapshot} = VariableSnapshot.new(attributes)

    assert snapshot.sections == %{
             "private" => %{revision: 0, value: %{"nested" => %{"enabled" => true}}}
           }

    assert snapshot.source_policy == %{"revision" => 0, "save_transcripts" => true}
  end

  defp baseline_snapshot do
    assert {:ok, snapshot} = VariableSnapshot.new(attributes(:baseline, 0))
    snapshot
  end

  defp attributed_snapshot do
    assert {:ok, snapshot} =
             attributes(:update, 1)
             |> Keyword.merge(
               command_id: "command-1",
               participant_id: "assistant-1",
               activation_id: "activation-1",
               source_participant_id: "caller-1",
               correlation_id: "turn-1",
               tool_call_id: "tool-1",
               section: "order",
               section_revision: 1,
               occurred_at: ~U[2026-09-09 11:41:02.000000Z]
             )
             |> VariableSnapshot.new()

    snapshot
  end

  defp attributed_fact(kind, sequence, occurred_at, payload) do
    assert {:ok, fact} =
             CallFact.new(
               id: "attributed-event-#{sequence}",
               kind: kind,
               sequence: sequence,
               tenant_key: "AAAAAAAAAAAAAAAA",
               call_id: "44444444-4444-4444-8444-444444444444",
               room_id: "55555555-5555-4555-8555-555555555555",
               incarnation_id: "rinc_archive-test",
               participant_id: "assistant-1",
               activation_id: "activation-1",
               source_participant_id: "caller-1",
               connection_id: "connection-1",
               command_id: "command-1",
               correlation_id: "turn-1",
               tool_call_id: "tool-1",
               occurred_at: occurred_at,
               source_policy: %{"revision" => 0},
               payload: payload
             )

    fact
  end

  defp call_fact(kind, sequence, payload, options \\ []) do
    assert {:ok, fact} =
             CallFact.new(
               id: "event-#{sequence}",
               kind: kind,
               sequence: sequence,
               tenant_key: "AAAAAAAAAAAAAAAA",
               call_id: "44444444-4444-4444-8444-444444444444",
               room_id: "55555555-5555-4555-8555-555555555555",
               incarnation_id: "rinc_archive-test",
               occurred_at: DateTime.add(~U[2026-09-09 11:41:00.000000Z], sequence, :second),
               source_policy: Keyword.get(options, :source_policy, %{"revision" => 0}),
               payload: payload
             )

    fact
  end

  defp attributes(kind, revision) do
    [
      id: "snapshot-#{revision}",
      kind: kind,
      tenant_key: "AAAAAAAAAAAAAAAA",
      call_id: "44444444-4444-4444-8444-444444444444",
      room_id: "55555555-5555-4555-8555-555555555555",
      incarnation_id: "rinc_archive-test",
      global_revision: revision,
      sections: %{"private" => %{revision: revision, value: %{"value" => "private-value"}}},
      source_policy: %{"revision" => 0, "save_transcripts" => true},
      occurred_at: ~U[2026-09-09 11:40:00.000000Z]
    ]
  end
end
