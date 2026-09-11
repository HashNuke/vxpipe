defmodule Vxpipe.Artifacts.S3ObjectReader do
  @moduledoc "Reads bounded byte ranges from one persisted S3-compatible object reference."

  alias Vxpipe.Artifacts.S3ReadClient

  @maximum_read_bytes 1_048_576
  @maximum_object_key_bytes 1_024
  @maximum_etag_bytes 1_024

  @spec read_range(map(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def read_range(object_reference, first, last, options) when is_list(options) do
    with {:ok, object_key, etag} <- object_reference(object_reference),
         :ok <- byte_range(first, last),
         {:ok, bucket} <- nonempty(options, :bucket),
         {:ok, client} <- client(options),
         {:ok, client_options} <- keyword(options, :client_options, []),
         {:ok, payload} <-
           client.read_range(bucket, object_key, first, last, etag, client_options),
         :ok <- expected_size(payload, last - first + 1) do
      {:ok, payload}
    end
  end

  def read_range(_object_reference, _first, _last, _options),
    do: {:error, :invalid_s3_reader_options}

  defp object_reference(%{"object_key" => object_key} = reference) do
    etag = Map.get(reference, "etag")

    valid? =
      Enum.all?(Map.keys(reference), &(&1 in ["object_key", "etag"])) and
        valid_string?(object_key, @maximum_object_key_bytes) and
        (is_nil(etag) or valid_string?(etag, @maximum_etag_bytes))

    if valid?, do: {:ok, object_key, etag}, else: {:error, :invalid_object_reference}
  end

  defp object_reference(_reference), do: {:error, :invalid_object_reference}

  defp byte_range(first, last)
       when is_integer(first) and is_integer(last) and first >= 0 and last >= first do
    if last - first + 1 <= @maximum_read_bytes,
      do: :ok,
      else: {:error, :read_too_large}
  end

  defp byte_range(_first, _last), do: {:error, :invalid_byte_range}

  defp client(options) do
    case Keyword.get(options, :client, Vxpipe.Artifacts.ExAwsS3ReadClient) do
      client when is_atom(client) ->
        if S3ReadClient.valid?(client), do: {:ok, client}, else: {:error, :invalid_s3_read_client}

      _invalid ->
        {:error, :invalid_s3_read_client}
    end
  end

  defp keyword(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_list(value) -> {:ok, value}
      _invalid -> {:error, :invalid_s3_reader_options}
    end
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :invalid_s3_reader_options}
    end
  end

  defp expected_size(payload, expected) when is_binary(payload) do
    if byte_size(payload) == expected,
      do: :ok,
      else: {:error, :invalid_range_response}
  end

  defp expected_size(_payload, _expected), do: {:error, :invalid_range_response}

  defp valid_string?(value, maximum),
    do: is_binary(value) and value != "" and byte_size(value) <= maximum
end
