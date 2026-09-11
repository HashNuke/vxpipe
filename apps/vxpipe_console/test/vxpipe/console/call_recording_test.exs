defmodule Vxpipe.Console.CallRecordingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{CallArtifact, Principal}

  alias Vxpipe.Console.{
    CallRecording,
    CallsRecordingBackend,
    TestCallRecordingArtifactRepository,
    TestCallRecordingBackend,
    TestCallRecordingObjectReader
  }

  alias Vxpipe.Console.CallRecording.{Reader, Source}

  @principal %Principal{
    tenant_key: "tenantkey1234567",
    api_key_id: "01234567-89ab-4cde-8fab-0123456789ab",
    scopes: MapSet.new([:calls])
  }

  test "opens one exact recording through the configured boundary" do
    source = source()
    backend = {TestCallRecordingBackend, {self(), {:ok, source}}}

    assert {:ok, ^source} =
             CallRecording.open(@principal, "call-public-id", "artifact-public-id",
               backend: backend
             )

    assert_receive {:open_call_recording, @principal, "call-public-id", "artifact-public-id"}
  end

  test "lists safe recording summaries through the configured boundary" do
    backend = {TestCallRecordingBackend, {self(), {:ok, []}}}

    assert {:ok, []} = CallRecording.list(@principal, "call-public-id", backend: backend)
    assert_receive {:list_call_recordings, @principal, "call-public-id"}
  end

  test "composes tenant-authorized artifact lookup with the trusted object reader" do
    artifact = artifact()

    options = [
      calls_options: [
        artifact_repository: {TestCallRecordingArtifactRepository, {self(), {:ok, artifact}}}
      ],
      recording_settings: [bucket: "recordings"],
      object_reader: TestCallRecordingObjectReader,
      object_reader_options: [observer: self(), payload: <<1, 2, 3, 4>>]
    ]

    assert {:ok, %Source{} = source} =
             CallsRecordingBackend.open(
               options,
               @principal,
               "call-public-id",
               "artifact-public-id"
             )

    assert_receive {:fetch_call_recording_artifact, "tenantkey1234567", "call-public-id",
                    "artifact-public-id"}

    assert {:ok, <<2, 3>>} = Reader.read_range(source.reader, 1, 2)

    assert_receive {:read_call_recording_object,
                    %{
                      "etag" => "recording-etag",
                      "object_key" => "calls/tenant/call/full-mix.s16le"
                    }, 1, 2, reader_options}

    assert Keyword.fetch!(reader_options, :bucket) == "recordings"
    assert Keyword.fetch!(reader_options, :observer) == self()
    assert Keyword.fetch!(reader_options, :payload) == <<1, 2, 3, 4>>
    assert Keyword.fetch!(reader_options, :client_options) == [request_options: []]
  end

  test "lists playable metadata without retaining a private object reference" do
    artifact = artifact()

    options = [
      calls_options: [
        artifact_repository: {TestCallRecordingArtifactRepository, {self(), {:ok, [artifact]}}}
      ],
      recording_settings: [bucket: "recordings"],
      object_reader: TestCallRecordingObjectReader,
      object_reader_options: [observer: self(), payload: <<1, 2, 3, 4>>]
    ]

    assert {:ok, [summary]} =
             CallsRecordingBackend.list(options, @principal, "call-public-id")

    assert_receive {:fetch_call_recording_artifacts, "tenantkey1234567", "call-public-id"}
    assert summary.id == "artifact-public-id"
    assert summary.kind == :full_mix
    assert summary.playable?
    refute Map.has_key?(summary, :object_key)
    refute Map.has_key?(summary, :object_reference)
    refute_receive {:read_call_recording_object, _, _, _, _}
  end

  test "does not claim metadata without a stored object is playable" do
    artifact = %{
      artifact()
      | id: "artifact-metadata-only",
        object_key: "private/metadata-only.s16le",
        object_reference: nil,
        status: :incomplete,
        terminal_reason: "completion_failed"
    }

    options = [
      calls_options: [
        artifact_repository: {TestCallRecordingArtifactRepository, {self(), {:ok, [artifact]}}}
      ],
      recording_settings: [bucket: "recordings"],
      object_reader: TestCallRecordingObjectReader,
      object_reader_options: [observer: self(), payload: <<1, 2, 3, 4>>]
    ]

    assert {:ok, [summary]} =
             CallsRecordingBackend.list(options, @principal, "call-public-id")

    refute summary.playable?
    assert summary.status == :incomplete
    assert summary.terminal_reason == "completion_failed"
    refute_receive {:read_call_recording_object, _, _, _, _}
  end

  defp source do
    {:ok, source} =
      Source.new(artifact(), {Vxpipe.Console.TestCallRecordingReader, {self(), <<1, 2, 3, 4>>}})

    source
  end

  defp artifact do
    %CallArtifact{
      id: "artifact-public-id",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :full_mix,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      object_key: "calls/tenant/call/full-mix.s16le",
      object_reference: %{
        "etag" => "recording-etag",
        "object_key" => "calls/tenant/call/full-mix.s16le"
      },
      sample_rate: 1,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 2,
      sample_count: 2,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end
end
