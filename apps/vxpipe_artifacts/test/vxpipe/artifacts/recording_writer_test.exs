defmodule Vxpipe.Artifacts.RecordingWriterTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.{RecordingWriter, TestObjectStore}
  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}

  test "adapts a room recording stream to one bounded artifact writer" do
    source = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    stream = %Stream{
      tenant_id: "tenant-test",
      call_id: "call-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      stream_id: "full-mix",
      mode: :full_mix,
      sample_rate: 48_000,
      channels: 2,
      sample_format: :s16le
    }

    options = [
      source: source,
      object_store: TestObjectStore,
      object_store_options: [observer: self()],
      maximum_pending_chunks: 2,
      drain_timeout_ms: 1_000,
      observer: self()
    ]

    assert {:ok, handle} = RecordingWriter.open(stream, options)
    writer_monitor = Process.monitor(handle.writer)

    assert_receive {:test_object_store_opened, _task, spec}
    assert spec.tenant_id == stream.tenant_id
    assert spec.call_id == stream.call_id
    assert spec.kind == :full_mix
    assert spec.channels == 2
    assert String.starts_with?(spec.artifact_id, "artifact_")
    assert String.ends_with?(spec.object_key, "/#{spec.artifact_id}.s16le")

    chunk = %Chunk{
      sequence: 0,
      offset_samples: 0,
      sample_count: 2,
      timestamp: 0,
      policy_revision: 4,
      source_participant_ids: ["alice", "bob"],
      payload:
        <<1::little-signed-16, 2::little-signed-16, 3::little-signed-16, 4::little-signed-16>>
    }

    assert :ok = RecordingWriter.offer(handle, chunk)
    assert_receive {:test_object_store_write, write_task, write_ref, artifact_chunk}
    assert artifact_chunk.sequence == 0
    assert artifact_chunk.sample_count == 2
    assert artifact_chunk.channels == 2
    assert artifact_chunk.payload == chunk.payload

    send(write_task, {:test_object_store_continue, write_ref})

    source_monitor = Process.monitor(source)
    send(source, :stop)
    assert_receive {:DOWN, ^source_monitor, :process, ^source, :normal}, 1_000
    assert_receive {:vxpipe_artifact_writer_draining, writer}

    assert_receive {:test_object_store_completed, _task, manifest}
    assert manifest.status == :complete
    assert manifest.sample_count == 2
    assert manifest.ended_offset_samples == 2

    assert_receive {:vxpipe_artifact_writer_finished, ^writer, result}
    assert result.manifest == manifest
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :normal}, 1_000
  end
end
