defmodule Vxpipe.CallEngine.Archive.SubscriberTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff, Subscriber, Supervisor}

  alias Vxpipe.CallEngine.{
    TestArchiveWriter,
    TestBlockingArchiveWriter,
    TestCollectingArchiveWriter
  }

  test "readiness requires a bound open producer but does not wait for archival storage" do
    subscriber =
      start_supervised!(
        {Subscriber,
         writer: {TestArchiveWriter, self()},
         maximum_pending_facts: 4,
         retry_delay_ms: 5,
         drain_timeout_ms: 1_000}
      )

    handoff = Subscriber.handoff(subscriber)
    assert {:ok, resource, :preparing} = Subscriber.readiness(subscriber)
    assert resource.kind == :archive
    assert :ok = Handoff.source_started(handoff, self())
    assert {:ok, ^resource, :ready} = Subscriber.readiness(subscriber)
    assert :ok = Handoff.offer(handoff, :retained_while_storage_waits)
    assert_receive {:test_archive_write, writer, :retained_while_storage_waits}
    assert {:ok, ^resource, :ready} = Subscriber.readiness(subscriber)

    monitor = Process.monitor(subscriber)
    assert :ok = Handoff.source_stopped(handoff, :finished)
    assert {:ok, ^resource, :failed} = Subscriber.readiness(subscriber)
    send(writer, {:test_archive_write_result, :ok})
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}
  end

  test "writes an explicit archive closure after retained room facts drain" do
    source_stopped_at = ~U[2026-09-12 20:00:00.123Z]

    handoff =
      open_archive(
        writer: {TestCollectingArchiveWriter, self()},
        now: fn -> source_stopped_at end
      )

    subscriber = handoff.subscriber
    monitor = Process.monitor(subscriber)
    source = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = Handoff.source_started(handoff, source)
    assert :ok = Handoff.offer(handoff, archive_fact())
    assert_receive {:test_archive_fact, %Fact{kind: :room_opened, sequence: 1}}

    Process.exit(source, :kill)

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :archive_stream_closed,
                      sequence: 2,
                      occurred_at: ^source_stopped_at,
                      payload: %{
                        "incomplete" => false,
                        "overflow" => 0,
                        "source_reason" => "killed",
                        "unavailable" => 0
                      }
                    }}

    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}
    assert %{accepted: 1, pending: 0} = Handoff.stats(handoff)
  end

  test "records overflow as a known-incomplete archive closure" do
    handoff =
      open_archive(
        maximum_pending_facts: 1,
        writer: {TestBlockingArchiveWriter, self()}
      )

    subscriber = handoff.subscriber
    monitor = Process.monitor(subscriber)
    source = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = Handoff.source_started(handoff, source)
    assert :ok = Handoff.offer(handoff, archive_fact())
    assert_receive {:test_archive_write, retained_writer, %Fact{kind: :room_opened}}

    assert {:error, :full} =
             Handoff.offer(handoff, %{archive_fact() | id: "event-dropped", sequence: 2})

    Process.exit(source, :kill)
    send(retained_writer, {:test_archive_write_result, :ok})

    assert_receive {:test_archive_write, completion_writer,
                    %Fact{
                      kind: :archive_stream_closed,
                      payload: %{"incomplete" => true, "overflow" => 1}
                    }}

    send(completion_writer, {:test_archive_write_result, :ok})
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}
    assert %{accepted: 1, overflow: 1, pending: 0} = Handoff.stats(handoff)
  end

  test "strictly bounds accepted facts while a writer is unavailable and drains after the room" do
    handoff = open_archive(maximum_pending_facts: 2)
    subscriber = handoff.subscriber
    subscriber_monitor = Process.monitor(subscriber)
    source = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = Handoff.source_started(handoff, source)
    assert :ok = Handoff.offer(handoff, :first)
    assert_receive {:test_archive_write, first_writer, :first}
    refute first_writer == subscriber

    assert :ok = Handoff.offer(handoff, :second)
    assert {:error, :full} = Handoff.offer(handoff, :overflow)

    assert %{
             accepted: 2,
             capacity: 2,
             discarded: 0,
             overflow: 1,
             pending: 2,
             unavailable: 0
           } = Handoff.stats(handoff)

    Process.exit(source, :kill)
    refute_receive {:DOWN, ^subscriber_monitor, :process, ^subscriber, _reason}, 50

    send(first_writer, {:test_archive_write_result, :ok})
    assert_receive {:test_archive_write, second_writer, :second}
    assert Process.alive?(subscriber)

    send(second_writer, {:test_archive_write_result, :ok})
    assert_receive {:DOWN, ^subscriber_monitor, :process, ^subscriber, :normal}

    assert %{accepted: 2, overflow: 1, pending: 0} = Handoff.stats(handoff)
  end

  test "retries a retained fact after storage recovery without accepting it twice" do
    handoff = open_archive(retry_delay_ms: 1)
    subscriber = handoff.subscriber
    monitor = Process.monitor(subscriber)

    assert :ok = Handoff.offer(handoff, :retained)
    assert_receive {:test_archive_write, first_writer, :retained}
    send(first_writer, {:test_archive_write_result, {:retry, :database_unavailable}})

    assert_receive {:test_archive_write, recovered_writer, :retained}
    assert %{accepted: 1, pending: 1, retries: 1} = Handoff.stats(handoff)

    send(recovered_writer, {:test_archive_write_result, :ok})
    assert eventually(fn -> Handoff.stats(handoff).pending == 0 end)

    assert :ok = Handoff.source_stopped(handoff, :test_complete)
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}
    assert %{accepted: 1, discarded: 0, pending: 0} = Handoff.stats(handoff)
  end

  test "a crashed subscriber makes later offers unavailable without restarting it" do
    handoff = open_archive()
    subscriber = handoff.subscriber
    monitor = Process.monitor(subscriber)

    Process.exit(subscriber, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :killed}

    assert {:error, :unavailable} = Handoff.offer(handoff, :after_crash)
    assert %{accepted: 0, pending: 0, unavailable: 1} = Handoff.stats(handoff)
  end

  test "bounds finalization and reports a retained fact discarded at drain expiry" do
    handoff = open_archive(drain_timeout_ms: 25)
    subscriber = handoff.subscriber
    monitor = Process.monitor(subscriber)
    source = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = Handoff.source_started(handoff, source)
    assert :ok = Handoff.offer(handoff, :never_finishes)
    assert_receive {:test_archive_write, writer, :never_finishes}
    writer_monitor = Process.monitor(writer)

    Process.exit(source, :kill)

    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :shutdown}
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}

    assert %{
             accepted: 1,
             discarded: 1,
             incomplete?: true,
             open?: false,
             pending: 0
           } = Handoff.stats(handoff)
  end

  defp open_archive(options \\ []) do
    options =
      Keyword.merge(
        [
          writer: {TestArchiveWriter, self()},
          maximum_pending_facts: 4,
          retry_delay_ms: 5,
          drain_timeout_ms: 1_000
        ],
        options
      )

    assert {:ok, handoff} = Supervisor.open(options)

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end

  defp archive_fact do
    Fact.new!(
      id: "event-open",
      kind: :room_opened,
      sequence: 1,
      tenant_id: "tenant-test",
      call_id: "call-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      occurred_at: ~U[2026-09-09 13:58:00.000000Z],
      source_policy: %{"revision" => 0},
      payload: %{}
    )
  end

  defp eventually(predicate, attempts \\ 100)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(5)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false
end
