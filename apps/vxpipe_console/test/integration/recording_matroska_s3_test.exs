defmodule Vxpipe.Console.RecordingMatroskaS3Test do
  @moduledoc """
  S3-compatible download path for the single Matroska recording.

  Requires a loopback S3-compatible server (moto) serving
  `VXPIPE_TEST_S3_ENDPOINT_URL` (default `http://127.0.0.1:18764`):

      moto_server -p 18764
      VXPIPE_TEST_S3_ENDPOINT_URL=http://127.0.0.1:18764 mix test \
        apps/vxpipe_console/test/integration/recording_matroska_s3_test.exs --include integration --only s3

  Each run uses a unique bucket that is deleted with its objects on exit.
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` stay set only because the
  production `ExAwsS3ReadClient` resolves credentials from the runtime
  environment; bucket/object setup and teardown pass per-request credentials
  instead. Set `VXPIPE_MATROSKA_EXPORT_PATH` to keep a copy of the download
  for manual `ffprobe` inspection. When `ffprobe` is available, the stream
  count and title tags are asserted; otherwise that assertion is explicitly
  skipped. No live ffmpeg dependency is required.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.CallArtifact

  alias Vxpipe.Console.{
    CallsRecordingBackend,
    RecordingMatroska,
    TestCallRecordingArtifactRepository
  }

  alias Vxpipe.Console.CallRecording.Source
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Console.TestCallRecordingReader

  @moduletag :integration
  @tag :s3

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"
  @route "/api/tenants/#{@tenant_key}/calls/call-public-id/recording.mka"
  @default_s3_endpoint_url "http://127.0.0.1:18764"
  @s3_region "us-east-1"
  @s3_access_key_id "moto-test-key"
  @s3_secret_access_key "moto-test-secret"

  setup do
    original_identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_recording_backend)
    original_access = System.get_env("AWS_ACCESS_KEY_ID")
    original_secret = System.get_env("AWS_SECRET_ACCESS_KEY")

    on_exit(fn ->
      if original_identity,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_identity),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)

      Application.put_env(:vxpipe_console, :call_recording_backend, original_backend)

      restore_env("AWS_ACCESS_KEY_ID", original_access)
      restore_env("AWS_SECRET_ACCESS_KEY", original_secret)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    # Production ExAwsS3ReadClient resolves credentials from the runtime
    # environment; direct ExAws setup/teardown below pass per-request
    # credentials so only the exercised reader needs the process env.
    System.put_env("AWS_ACCESS_KEY_ID", @s3_access_key_id)
    System.put_env("AWS_SECRET_ACCESS_KEY", @s3_secret_access_key)

    :ok
  end

  test "downloads recording.mka through real S3 range reads" do
    endpoint_url = s3_endpoint_url()
    settings = s3_settings(endpoint_url)
    overrides = exaws_overrides(settings)

    bucket = "vxp-matroska-test-#{Ecto.UUID.generate()}"
    prefix = "calls/test/#{Ecto.UUID.generate()}"
    assert {:ok, _} = bucket |> ExAws.S3.put_bucket(@s3_region) |> ExAws.request(overrides)

    room_key = "#{prefix}/room.s16le"
    caller_key = "#{prefix}/caller.s16le"
    reconnect_key = "#{prefix}/caller-1.s16le"
    object_keys = [room_key, caller_key, reconnect_key]

    on_exit(fn ->
      for key <- object_keys do
        _ = bucket |> ExAws.S3.delete_object(key) |> ExAws.request(overrides)
      end

      _ = ExAws.S3.delete_bucket(bucket) |> ExAws.request(overrides)
    end)

    room_payload = :binary.copy(<<16, 0>>, 48_000)
    caller_payload = :binary.copy(<<32, 0>>, 48_000)
    reconnect_payload = :binary.copy(<<48, 0>>, 48_000)

    assert {:ok, _} =
             ExAws.S3.put_object(bucket, room_key, room_payload) |> ExAws.request(overrides)

    assert {:ok, _} =
             ExAws.S3.put_object(bucket, caller_key, caller_payload) |> ExAws.request(overrides)

    assert {:ok, _} =
             ExAws.S3.put_object(bucket, reconnect_key, reconnect_payload)
             |> ExAws.request(overrides)

    # Production reader verifies one bounded range directly against moto.
    assert {:ok, ^room_payload} =
             Vxpipe.Artifacts.S3ObjectReader.read_range(
               %{"object_key" => room_key},
               0,
               byte_size(room_payload) - 1,
               bucket: bucket,
               client_options: [request_options: settings]
             )

    artifacts = [
      room_artifact(room_key),
      caller_artifact(caller_key),
      reconnect_artifact(reconnect_key)
    ]

    Application.put_env(
      :vxpipe_console,
      :call_recording_backend,
      {CallsRecordingBackend,
       [
         calls_options: [
           artifact_repository: {TestCallRecordingArtifactRepository, {self(), {:ok, artifacts}}}
         ],
         recording_settings: [bucket: bucket, region: @s3_region, endpoint: endpoint_url]
       ]}
    )

    conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost#{@route}")

    body = response(conn, 200)

    assert binary_part(body, 0, 4) == <<0x1A, 0x45, 0xDF, 0xA3>>
    assert body =~ "room"
    assert body =~ "caller"
    assert body =~ "caller-1"

    assert Plug.Conn.get_resp_header(conn, "content-type") == ["audio/x-matroska"]
    assert_receive {:fetch_call_recording_artifacts, @tenant_key, "call-public-id"}

    # Byte ranges use the production reader through the endpoint.
    range_conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=0-99")
      |> get("https://localhost#{@route}")

    assert byte_size(response(range_conn, 206)) == 100

    assert [range] = Plug.Conn.get_resp_header(range_conn, "content-range")
    assert String.starts_with?(range, "bytes 0-99/")

    # A range straddling the first audio block boundary must return the exact
    # file bytes through the production reader, not just a byte count.
    {:ok, local_matroska} =
      RecordingMatroska.new(local_sources(room_key, caller_key, reconnect_key))

    first_audio =
      local_matroska.prefix_size + local_matroska.cluster_header_len +
        local_matroska.block_header_len

    assert first_audio > 7
    block_first = first_audio - 7
    block_last = first_audio + 25

    block_conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=#{block_first}-#{block_last}")
      |> get("https://localhost#{@route}")

    assert response(block_conn, 206) ==
             binary_part(body, block_first, block_last - block_first + 1)

    assert Plug.Conn.get_resp_header(block_conn, "content-range") == [
             "bytes #{block_first}-#{block_last}/#{byte_size(body)}"
           ]

    late_first = max(byte_size(body) - 200, 0)
    late_last = byte_size(body) - 1

    late_conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=#{late_first}-#{late_last}")
      |> get("https://localhost#{@route}")

    assert response(late_conn, 206) == binary_part(body, late_first, late_last - late_first + 1)

    case System.get_env("VXPIPE_MATROSKA_EXPORT_PATH") do
      nil -> :ok
      "" -> :ok
      path -> File.write!(path, body)
    end

    case System.find_executable("ffprobe") do
      nil ->
        IO.puts("ffprobe absent, skipping Matroska stream/title assertions")

      ffprobe ->
        path = Path.join(System.tmp_dir!(), "recording-#{Ecto.UUID.generate()}.mka")
        File.write!(path, body)

        try do
          {output, 0} =
            System.cmd(ffprobe, [
              "-v",
              "error",
              "-show_entries",
              "stream=index,codec_name,channels,sample_rate:stream_tags=title",
              "-of",
              "json",
              path
            ])

          {:ok, report} = JSON.decode(output)
          streams = Map.fetch!(report, "streams")

          assert length(streams) == 3

          titles =
            streams
            |> Enum.map(&get_in(&1, ["tags", "title"]))
            |> Enum.sort()

          assert titles == ["caller", "caller-1", "room"]

          assert Enum.all?(streams, fn stream ->
                   stream["codec_name"] in ["pcm_s16le", "pcm_s16le_planar"] and
                     stream["channels"] == 1 and stream["sample_rate"] == "48000"
                 end)
        after
          File.rm(path)
        end
    end
  end

  defp s3_endpoint_url do
    System.get_env("VXPIPE_TEST_S3_ENDPOINT_URL") || @default_s3_endpoint_url
  end

  defp s3_settings(endpoint_url) do
    uri = URI.parse(endpoint_url)

    scheme =
      case uri.scheme do
        "https" -> "https://"
        _ -> "http://"
      end

    port = uri.port || if scheme == "https://", do: 443, else: 80

    [
      region: @s3_region,
      scheme: scheme,
      host: uri.host || "127.0.0.1",
      port: port,
      virtual_host: false
    ]
  end

  defp exaws_overrides(settings) do
    settings ++
      [
        access_key_id: @s3_access_key_id,
        secret_access_key: @s3_secret_access_key,
        http_client: ExAws.Request.Req
      ]
  end

  defp local_sources(room_key, caller_key, reconnect_key) do
    [
      local_source(room_artifact(room_key), :binary.copy(<<16, 0>>, 48_000)),
      local_source(caller_artifact(caller_key), :binary.copy(<<32, 0>>, 48_000)),
      local_source(reconnect_artifact(reconnect_key), :binary.copy(<<48, 0>>, 48_000))
    ]
  end

  defp local_source(artifact, payload) do
    {:ok, source} = Source.new(artifact, {TestCallRecordingReader, {self(), payload}})
    source
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp room_artifact(object_key) do
    %CallArtifact{
      id: "artifact-room",
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: object_key,
      object_reference: %{"object_key" => object_key},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 48_000,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp caller_artifact(object_key) do
    %CallArtifact{
      id: "artifact-caller",
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :participant_track,
      participant_id: "part_caller",
      connection_id: "conn_caller",
      track_id: "track_caller",
      participant_key: "caller",
      reconnection: 0,
      object_key: object_key,
      object_reference: %{"object_key" => object_key},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 48_000,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp reconnect_artifact(object_key) do
    %CallArtifact{
      id: "artifact-caller-1",
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :participant_track,
      participant_id: "part_caller",
      connection_id: "conn_caller_2",
      track_id: "track_caller_2",
      participant_key: "caller",
      reconnection: 1,
      object_key: object_key,
      object_reference: %{"object_key" => object_key},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 48_000,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end
end
