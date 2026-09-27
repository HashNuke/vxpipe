defmodule Vxpipe.Artifacts.Integration.S3CompatibleObjectStoreTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Manifest, S3ObjectReader, S3ObjectStore}

  @moduletag :integration
  @moduletag live_provider: "s3"
  @moduletag :s3_live
  @moduletag timeout: 60_000

  @part_size_bytes 5 * 1_024 * 1_024

  @moduletag skip: System.get_env("VXPIPE_LIVE") != "1"

  setup do
    bucket = System.fetch_env!("VXPIPE_S3_INTEGRATION_BUCKET")
    region = System.get_env("VXPIPE_S3_INTEGRATION_REGION", "us-east-1")

    request_options =
      System.fetch_env!("VXPIPE_S3_INTEGRATION_ENDPOINT")
      |> request_options(region)

    :ok = ensure_bucket(bucket, region, request_options)

    {:ok, bucket: bucket, request_options: request_options}
  end

  test "multipart upload is readable byte-for-byte from compatible storage", context do
    object_key =
      "vxpipe-integration/#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}.s16le"

    spec = artifact_spec(object_key)

    on_exit(fn ->
      _outcome =
        context.bucket
        |> ExAws.S3.delete_object(object_key)
        |> ExAws.request(context.request_options)
    end)

    options = [
      bucket: context.bucket,
      client_options: [request_options: context.request_options],
      part_size_bytes: @part_size_bytes
    ]

    first_payload = :binary.copy(<<1, 0>>, div(@part_size_bytes, 2))
    final_payload = <<2, 0, 3, 0>>
    expected = first_payload <> final_payload

    assert {:ok, session} = S3ObjectStore.open(spec, options)

    assert {:ok, session} =
             S3ObjectStore.write_chunk(session, chunk(0, 0, first_payload), options)

    first_samples = div(byte_size(first_payload), 2)

    assert {:ok, session} =
             S3ObjectStore.write_chunk(
               session,
               chunk(1, first_samples, final_payload),
               options
             )

    total_samples = div(byte_size(expected), 2)
    manifest = Manifest.build(spec, progress(total_samples), 0, :normal)

    assert {:ok, artifact} = S3ObjectStore.complete(session, manifest, options)
    assert artifact.object_key == object_key

    assert {:ok, %{body: body}} =
             context.bucket
             |> ExAws.S3.get_object(object_key)
             |> ExAws.request(context.request_options)

    assert body == expected

    object_reference = %{"object_key" => object_key, "etag" => artifact.etag}

    assert {:ok, <<1, 0, 2, 0, 3, 0>>} =
             S3ObjectReader.read_range(
               object_reference,
               @part_size_bytes - 2,
               @part_size_bytes + 3,
               bucket: context.bucket,
               client_options: [request_options: context.request_options]
             )
  end

  defp ensure_bucket(bucket, region, request_options) do
    case bucket |> ExAws.S3.head_bucket() |> ExAws.request(request_options) do
      {:ok, _response} ->
        :ok

      {:error, _reason} ->
        case bucket |> ExAws.S3.put_bucket(region) |> ExAws.request(request_options) do
          {:ok, _response} ->
            :ok

          {:error, _reason} ->
            raise "S3-compatible integration bucket unavailable"
        end
    end
  end

  defp request_options(endpoint, region) do
    case URI.parse(endpoint) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             is_integer(port) and path in [nil, "", "/"] ->
        [
          scheme: scheme <> "://",
          host: host,
          port: port,
          region: region,
          virtual_host: false,
          http_client: ExAws.Request.Req
        ]

      _invalid ->
        raise "VXPIPE_S3_INTEGRATION_ENDPOINT must be an HTTP(S) root origin with a port"
    end
  end

  defp artifact_spec(object_key) do
    %ArtifactSpec{
      tenant_id: "tenant-integration",
      call_id: "call-integration",
      room_id: "room-integration",
      incarnation_id: "incarnation-integration",
      artifact_id: "artifact-integration",
      object_key: object_key,
      kind: :full_mix,
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le
    }
  end

  defp chunk(sequence, offset_samples, payload) do
    %Chunk{
      sequence: sequence,
      offset_samples: offset_samples,
      sample_count: div(byte_size(payload), 2),
      channels: 1,
      timestamp: offset_samples,
      policy_revision: 0,
      source_participant_ids: [],
      payload: payload
    }
  end

  defp progress(sample_count) do
    %{
      accepted_chunks: 2,
      failed_chunks: 0,
      sample_count: sample_count,
      started_offset_samples: 0,
      ended_offset_samples: sample_count,
      gaps: []
    }
  end
end
