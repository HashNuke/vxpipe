defmodule Vxpipe.Artifacts.WriterTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.{Chunk, Handoff, TestObjectStore, Writer, Writers}

  test "a supervised bounded writer drains accepted chunks after its source exits" do
    source = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    spec = %{
      tenant_id: "tenant-test",
      call_id: "call-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      artifact_id: "artifact-test",
      object_key: "tenant-test/call-test/full-mix.raw",
      kind: :full_mix,
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le
    }

    options = [
      source: source,
      spec: spec,
      object_store: TestObjectStore,
      object_store_options: [observer: self()],
      maximum_pending_chunks: 2,
      drain_timeout_ms: 1_000,
      observer: self()
    ]

    assert {:ok, writer} = Writers.start_writer(options)
    writer_monitor = Process.monitor(writer)
    handoff = Writer.handoff(writer)

    assert_receive {:test_object_store_opened, _task, opened_spec}
    assert opened_spec.artifact_id == "artifact-test"

    first = chunk(0, 0)
    second = chunk(1, 960)
    rejected = chunk(2, 1_920)

    assert :ok = Handoff.offer(handoff, first)
    assert_receive {:test_object_store_write, first_task, first_ref, ^first}

    assert :ok = Handoff.offer(handoff, second)
    assert {:error, :full} = Handoff.offer(handoff, rejected)

    send(first_task, {:test_object_store_continue, first_ref})
    assert_receive {:test_object_store_write, second_task, second_ref, ^second}

    source_monitor = Process.monitor(source)
    send(source, :stop)
    assert_receive {:DOWN, ^source_monitor, :process, ^source, :normal}, 1_000
    assert_receive {:vxpipe_artifact_writer_draining, ^writer}

    assert {:error, :closed} = Handoff.offer(handoff, chunk(3, 2_880))

    send(second_task, {:test_object_store_continue, second_ref})

    assert_receive {:test_object_store_completed, _task, manifest}
    assert manifest.status == :incomplete
    assert manifest.accepted_chunks == 2
    assert manifest.rejected_chunks == 1
    assert manifest.sample_count == 1_920

    assert_receive {:vxpipe_artifact_writer_finished, ^writer, result}
    assert result.manifest == manifest
    assert result.artifact.object_key == spec.object_key
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :normal}, 1_000
  end

  defp chunk(sequence, offset_samples) do
    %Chunk{
      sequence: sequence,
      offset_samples: offset_samples,
      sample_count: 960,
      timestamp: offset_samples,
      policy_revision: 0,
      source_participant_ids: [],
      payload: :binary.copy(<<0, 0>>, 960)
    }
  end
end
