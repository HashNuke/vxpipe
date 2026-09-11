defmodule Vxpipe.Artifacts.TestS3ReadClient do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3ReadClient

  @impl true
  def read_range(bucket, object_key, first, last, etag, options) do
    observer = Keyword.fetch!(options, :observer)
    payload = Keyword.fetch!(options, :payload)
    send(observer, {:test_s3_range_read, bucket, object_key, first, last, etag})
    {:ok, binary_part(payload, first, last - first + 1)}
  end
end
