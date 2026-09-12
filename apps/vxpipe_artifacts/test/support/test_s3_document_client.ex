defmodule Vxpipe.Artifacts.TestS3DocumentClient do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3DocumentClient

  @impl true
  def put_new(bucket, object_key, contents, checksum, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_document_put, bucket, object_key, contents, checksum})
    Keyword.get(options, :put_result, {:ok, %{etag: "etag-document"}})
  end

  @impl true
  def head(bucket, object_key, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_document_head, bucket, object_key})
    Keyword.get(options, :head_result, {:error, :not_found})
  end
end
