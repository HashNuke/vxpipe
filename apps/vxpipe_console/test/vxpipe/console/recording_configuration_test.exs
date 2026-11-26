defmodule Vxpipe.Console.RecordingConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.RecordingConfiguration

  test "stays disabled without storage, regardless of persistence" do
    assert {:ok, [enabled: false]} = RecordingConfiguration.build([])
    assert {:ok, [enabled: false]} = RecordingConfiguration.build(persistence_enabled: true)
    assert {:ok, [enabled: false]} = RecordingConfiguration.build(bucket: "")
    assert {:ok, [enabled: false]} = RecordingConfiguration.build(bucket: "   ")
  end

  test "stays disabled when persistence is missing, even with a bucket" do
    assert {:ok, [enabled: false]} =
             RecordingConfiguration.build(bucket: "vxpipe-call-artifacts")

    assert {:ok, [enabled: false]} =
             RecordingConfiguration.build(
               bucket: "vxpipe-call-artifacts",
               persistence_enabled: false
             )
  end

  test "storage and persistence together enable the trusted S3 writer" do
    settings = [
      persistence_enabled: true,
      bucket: "vxpipe-call-artifacts",
      region: "eu-west-2",
      endpoint: "http://127.0.0.1:9000"
    ]

    assert {:ok, recording} = RecordingConfiguration.build(settings)

    assert [
             enabled: true,
             targets: [:room_track, :individual_tracks],
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

    assert {:error, :recording_bucket_required} = RecordingConfiguration.playback([])
  end

  test "rejects malformed storage endpoints instead of disabling capture" do
    assert {:error, :invalid_recording_endpoint} =
             RecordingConfiguration.build(
               persistence_enabled: true,
               bucket: "calls",
               endpoint: "ftp://objects.example.test"
             )
  end

  test "recording and playback reject invalid endpoint ports before opening storage" do
    for port <- ["bad", "-1", "0", "65536", "99999"] do
      settings = [
        persistence_enabled: true,
        bucket: "call-artifacts",
        endpoint: "http://objects.example.test:" <> port
      ]

      assert {:error, :invalid_recording_endpoint} = RecordingConfiguration.build(settings)
      assert {:error, :invalid_recording_endpoint} = RecordingConfiguration.playback(settings)
    end
  end
end
