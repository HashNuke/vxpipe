defmodule Vxpipe.Artifacts.ExAwsS3DocumentClient do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3DocumentClient

  @impl true
  def put_new(bucket, object_key, contents, checksum, options) do
    put_options = [
      content_type: "application/json",
      if_none_match: "*",
      meta: [vxpipe_sha256: Base.encode16(checksum, case: :lower)]
    ]

    bucket
    |> ExAws.S3.put_object(object_key, contents, put_options)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{headers: headers}} -> {:ok, %{etag: header(headers, "etag")}}
      {:error, {:http_error, 412, _body}} -> {:error, :already_exists}
      {:error, reason} -> {:error, reason}
      {:ok, _invalid} -> {:error, :invalid_put_response}
    end
  end

  @impl true
  def head(bucket, object_key, options) do
    bucket
    |> ExAws.S3.head_object(object_key)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{headers: headers}} -> head_metadata(headers)
      {:error, reason} -> {:error, reason}
      {:ok, _invalid} -> {:error, :invalid_head_response}
    end
  end

  defp head_metadata(headers) when is_list(headers) do
    with checksum when is_binary(checksum) <- header(headers, "x-amz-meta-vxpipe-sha256"),
         {:ok, checksum} <- Base.decode16(checksum, case: :mixed),
         true <- byte_size(checksum) == 32 do
      {:ok, %{checksum: checksum, etag: header(headers, "etag")}}
    else
      _invalid -> {:error, :missing_document_checksum}
    end
  end

  defp head_metadata(_headers), do: {:error, :invalid_head_response}

  defp header(headers, expected_name) do
    Enum.find_value(headers, fn
      {name, value} ->
        if name |> to_string() |> String.downcase() == expected_name, do: to_string(value)

      _invalid ->
        nil
    end)
  end

  defp request_options(options) do
    options
    |> Keyword.get(:request_options, [])
    |> Keyword.put_new(:http_client, ExAws.Request.Req)
  end
end
