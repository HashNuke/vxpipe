defmodule Vxpipe.Artifacts.TestS3Client do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3Client

  @impl true
  def initiate(bucket, object_key, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_s3_initiated, bucket, object_key})
    {:ok, "upload-test"}
  end

  @impl true
  def upload_part(bucket, object_key, upload_id, part_number, payload, options) do
    observer = Keyword.fetch!(options, :observer)

    send(
      observer,
      {:test_s3_part_uploaded, bucket, object_key, upload_id, part_number, payload}
    )

    {:ok, "etag-#{part_number}"}
  end

  @impl true
  def complete(bucket, object_key, upload_id, parts, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_s3_completed, bucket, object_key, upload_id, parts})
    {:ok, %{object_key: object_key, etag: "complete-etag"}}
  end

  @impl true
  def abort(bucket, object_key, upload_id, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_s3_aborted, bucket, object_key, upload_id})
    :ok
  end
end
