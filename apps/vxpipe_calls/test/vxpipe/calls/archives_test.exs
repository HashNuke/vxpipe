defmodule Vxpipe.Calls.ArchivesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Principal, TestArchiveRepository, VariableSnapshot}

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
      |> Keyword.put(:source_policy, %{revision: 0, save_transcripts: true})

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
