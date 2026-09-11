defmodule Vxpipe.Artifacts.ExAwsS3ReadClient do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.S3ReadClient

  @impl true
  def read_range(bucket, object_key, first, last, etag, options) do
    get_options =
      [range: "bytes=#{first}-#{last}"]
      |> maybe_match(etag)

    bucket
    |> ExAws.S3.get_object(object_key, get_options)
    |> ExAws.request(request_options(options))
    |> case do
      {:ok, %{body: body}} when is_binary(body) -> {:ok, body}
      {:ok, _invalid} -> {:error, :invalid_read_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_match(options, nil), do: options
  defp maybe_match(options, etag), do: Keyword.put(options, :if_match, etag)

  defp request_options(options) do
    options
    |> Keyword.get(:request_options, [])
    |> Keyword.put_new(:http_client, ExAws.Request.Req)
  end
end
