defmodule Vxpipe.Persistence.EctoStorageResilienceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor

  alias Vxpipe.Persistence.{
    EctoStorage,
    TestRecoveringArchiveRepository
  }

  test "retries EctoStorage after its repository crashes and closes without duplicates" do
    repository =
      start_supervised!({TestRecoveringArchiveRepository, mode: :raise, observer: self()})

    assert {:ok, handoff} =
             ArchiveSupervisor.open(
               writer:
                 {EctoStorage,
                  [archive_repository: TestRecoveringArchiveRepository.repository(repository)]},
               maximum_pending_facts: 4,
               retry_delay_ms: 5,
               drain_timeout_ms: 1_000
             )

    source = spawn(fn -> Process.sleep(:infinity) end)
    assert :ok = Handoff.source_started(handoff, source)
    assert :ok = Handoff.offer(handoff, engine_fact())

    assert_receive {:test_archive_repository_attempt, %Vxpipe.Calls.CallFact{}, :raise}, 1_000
    assert_receive {:test_archive_repository_attempt, %Vxpipe.Calls.CallFact{}, :raise}, 1_000
    assert %{pending: 1, retries: retries} = Handoff.stats(handoff)
    assert retries > 0

    TestRecoveringArchiveRepository.recover(repository)

    assert_receive {:test_archive_repository_stored,
                    %Vxpipe.Calls.CallFact{kind: :room_opened}},
                   1_000

    subscriber_monitor = Process.monitor(handoff.subscriber)
    Process.exit(source, :kill)
    assert_receive {:DOWN, ^subscriber_monitor, :process, _subscriber, :normal}, 2_000

    facts = TestRecoveringArchiveRepository.facts(repository)

    assert Enum.map(facts, & &1.kind) == [:room_opened, :archive_stream_closed]
    assert facts |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 2
  end

  defp engine_fact do
    Fact.new!(
      id: "event-ecto-recovery",
      kind: :room_opened,
      sequence: 1,
      tenant_id: "tenant-recovery",
      call_id: "call-recovery",
      room_id: "room-recovery",
      incarnation_id: "incarnation-recovery",
      occurred_at: ~U[2026-09-09 14:34:00.000000Z],
      source_policy: %{"revision" => 0},
      payload: %{}
    )
  end
end
