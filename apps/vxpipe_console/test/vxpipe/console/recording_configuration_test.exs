defmodule Vxpipe.Console.RecordingConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.RecordingConfiguration

  test "keeps recording disabled unless the host explicitly enables it" do
    assert {:ok, [enabled: false]} = RecordingConfiguration.build([])
    assert {:ok, [enabled: false]} = RecordingConfiguration.build(enabled: "false")
  end

  test "builds the trusted S3 writer and metadata adapter from host settings" do
    settings = [
      enabled: "true",
      persistence_enabled: true,
      bucket: "vxpipe-call-artifacts",
      region: "eu-west-2",
      endpoint: "http://127.0.0.1:9000"
    ]

    assert {:ok, recording} = RecordingConfiguration.build(settings)

    assert [
             enabled: true,
             targets: [:full_mix, :individual_tracks],
             maximum_egress_frames: 100,
             maximum_pull_frames: 16,
             writer: {Vxpipe.Artifacts.RecordingWriter, writer_options}
           ] = recording

    assert [
             object_store: Vxpipe.Artifacts.S3ObjectStore,
             object_store_options: object_store_options,
             maximum_pending_chunks: 100,
             drain_timeout_ms: 30_000,
             metadata: metadata
           ] = writer_options

    assert [
             bucket: "vxpipe-call-artifacts",
             client_options: [
               request_options: [
                 region: "eu-west-2",
                 scheme: "http://",
                 host: "127.0.0.1",
                 port: 9000,
                 virtual_host: false
               ]
             ]
           ] = object_store_options

    assert [
             writer: {Vxpipe.Persistence.EctoStorage, []},
             maximum_attempts: 5,
             retry_delay_ms: 250,
             write_timeout_ms: 5_000
           ] = metadata
  end

  test "uses ExAws defaults when no region or endpoint override is configured" do
    assert {:ok, recording} =
             RecordingConfiguration.build(
               enabled: "1",
               persistence_enabled: true,
               bucket: "vxpipe-call-artifacts"
             )

    {Vxpipe.Artifacts.RecordingWriter, writer_options} = Keyword.fetch!(recording, :writer)
    object_store_options = Keyword.fetch!(writer_options, :object_store_options)

    assert [bucket: "vxpipe-call-artifacts", client_options: [request_options: []]] =
             object_store_options
  end

  test "builds trusted playback reads independently of capture enablement" do
    settings = [
      enabled: false,
      bucket: "vxpipe-call-artifacts",
      region: "eu-west-2",
      endpoint: "http://127.0.0.1:9000"
    ]

    assert {:ok,
            [
              bucket: "vxpipe-call-artifacts",
              client_options: [
                request_options: [
                  region: "eu-west-2",
                  scheme: "http://",
                  host: "127.0.0.1",
                  port: 9000,
                  virtual_host: false
                ]
              ]
            ]} = RecordingConfiguration.playback(settings)

    assert {:error, :recording_bucket_required} = RecordingConfiguration.playback(enabled: false)
  end

  test "rejects incomplete or malformed enabled host settings" do
    assert {:error, :recording_persistence_required} =
             RecordingConfiguration.build(enabled: "true", bucket: "calls")

    assert {:error, :recording_bucket_required} =
             RecordingConfiguration.build(enabled: "true", persistence_enabled: true)

    assert {:error, :invalid_recording_endpoint} =
             RecordingConfiguration.build(
               enabled: "true",
               persistence_enabled: true,
               bucket: "calls",
               endpoint: "ftp://objects.example.test"
             )

    assert {:error, :invalid_recording_enabled} =
             RecordingConfiguration.build(enabled: "sometimes")
  end
end
