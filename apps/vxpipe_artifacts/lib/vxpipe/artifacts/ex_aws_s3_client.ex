defmodule Vxpipe.Artifacts.ExAwsS3Client do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3Client

  @impl true
  def initiate(bucket, object_key, options) do
    initiate_options =
      options
      |> Keyword.get(:initiate_options, [])
      |> Keyword.put_new(:content_type, "application/octet-stream")

    bucket
    |> ExAws.S3.initiate_multipart_upload(object_key, initiate_options)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{body: %{upload_id: upload_id}}} when is_binary(upload_id) and upload_id != "" ->
        {:ok, upload_id}

      {:ok, _invalid} ->
        {:error, :invalid_initiate_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def upload_part(bucket, object_key, upload_id, part_number, payload, options) do
    bucket
    |> ExAws.S3.upload_part(object_key, upload_id, part_number, payload)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{headers: headers}} -> etag(headers)
      {:error, reason} -> {:error, reason}
      {:ok, _invalid} -> {:error, :invalid_upload_part_response}
    end
  end

  @impl true
  def complete(bucket, object_key, upload_id, parts, options) do
    bucket
    |> ExAws.S3.complete_multipart_upload(object_key, upload_id, parts)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{body: body}} when is_map(body) ->
        {:ok,
         %{
           object_key: object_key,
           etag: Map.get(body, :etag),
           location: Map.get(body, :location)
         }}

      {:error, reason} ->
        {:error, reason}

      {:ok, _invalid} ->
        {:error, :invalid_complete_response}
    end
  end

  @impl true
  def abort(bucket, object_key, upload_id, options) do
    bucket
    |> ExAws.S3.abort_multipart_upload(object_key, upload_id)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp etag(headers) when is_list(headers) do
    case Enum.find_value(headers, &etag_header/1) do
      nil -> {:error, :missing_part_etag}
      value -> {:ok, value}
    end
  end

  defp etag(_headers), do: {:error, :invalid_upload_part_response}

  defp etag_header({name, value}) do
    if name |> to_string() |> String.downcase() == "etag", do: to_string(value)
  end

  defp etag_header(_header), do: nil

  defp request_options(options) do
    options
    |> Keyword.get(:request_options, [])
    |> Keyword.put_new(:http_client, ExAws.Request.Req)
  end
end
