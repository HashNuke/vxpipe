defmodule Vxpipe.Artifacts.S3DocumentStore do
  @moduledoc "Conditionally writes immutable JSON documents to an S3-compatible object store."

  @behaviour Vxpipe.Artifacts.DocumentObjectStore

  alias Vxpipe.Artifacts.{Document, S3DocumentClient}

  @impl true
  def put(%Document{} = document, options) when is_list(options) do
    with {:ok, bucket} <- nonempty(options, :bucket),
         {:ok, client} <- client(options),
         {:ok, client_options} <- keyword(options, :client_options, []) do
      put_or_verify(client, bucket, document, client_options)
    end
  end

  def put(_document, _options), do: {:error, :invalid_s3_document_options}

  defp put_or_verify(client, bucket, document, options) do
    case client.put_new(
           bucket,
           document.object_key,
           document.contents,
           document.checksum,
           options
         ) do
      {:ok, receipt} -> reference(document.object_key, receipt)
      {:error, :already_exists} -> verify_existing(client, bucket, document, options)
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_put_response}
    end
  end

  defp verify_existing(client, bucket, document, options) do
    case client.head(bucket, document.object_key, options) do
      {:ok, %{checksum: checksum} = receipt} when checksum == document.checksum ->
        reference(document.object_key, receipt)

      {:ok, %{checksum: _different}} ->
        {:error, :object_key_conflict}

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_head_response}
    end
  end

  defp reference(object_key, receipt) when is_map(receipt) do
    etag = Map.get(receipt, :etag) || Map.get(receipt, "etag")
    {:ok, %{"object_key" => object_key, "etag" => etag}}
  end

  defp client(options) do
    case Keyword.get(options, :client, Vxpipe.Artifacts.ExAwsS3DocumentClient) do
      client when is_atom(client) ->
        if S3DocumentClient.valid?(client),
          do: {:ok, client},
          else: {:error, :invalid_s3_document_client}

      _invalid ->
        {:error, :invalid_s3_document_client}
    end
  end

  defp keyword(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_list(value) -> {:ok, value}
      _invalid -> {:error, :invalid_s3_document_options}
    end
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :invalid_s3_document_options}
    end
  end
end
