defmodule Vxpipe.Console.IntegrationsDirectory.Transport do
  @moduledoc """
  Bounded anonymous HTTP transport for the public directory.

  Successful JSON remains untrusted until the directory client validates its
  schema and request identity. No upstream body is included in errors.
  """

  @max_bytes 1_048_576

  def fetch(request, options \\ []) do
    headers = conditional_headers(request.headers, Keyword.get(options, :etag))

    [
      url: request.url,
      params: request.params,
      headers: headers,
      redirect: false,
      retry: false,
      decode_body: false,
      compressed: false,
      receive_timeout: 5_000,
      finch: [
        request_timeout: 5_000,
        pool_timeout: 5_000,
        conn_opts: [transport_opts: [timeout: 5_000]]
      ],
      into: &receive_chunk/2
    ]
    |> Keyword.merge(Keyword.take(options, [:plug]))
    |> Req.get()
    |> decode_response()
  end

  defp conditional_headers(headers, etag) when is_binary(etag) and byte_size(etag) <= 1024,
    do: [{"if-none-match", etag} | headers]

  defp conditional_headers(headers, _etag), do: headers

  defp receive_chunk({:data, data}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(data) > @max_bytes do
      {:halt, {request, %{response | body: :too_large}}}
    else
      {:cont, {request, %{response | body: body <> data}}}
    end
  end

  defp decode_response({:error, _reason}), do: {:error, :unavailable}
  defp decode_response({:ok, %{body: :too_large}}), do: {:error, :response_too_large}
  defp decode_response({:ok, %{status: 304}}), do: :not_modified

  defp decode_response({:ok, %{status: 200} = response}) do
    with [content_type | _] <- Req.Response.get_header(response, "content-type"),
         true <- content_type |> String.split(";") |> hd() |> String.trim() == "application/json",
         [] <- Req.Response.get_header(response, "content-encoding"),
         {:ok, body} when is_map(body) <- JSON.decode(response.body) do
      {:ok, %{body: body, etag: response |> Req.Response.get_header("etag") |> List.first()}}
    else
      _invalid -> {:error, :invalid_response}
    end
  end

  defp decode_response({:ok, %{status: 429} = response}),
    do: {:error, {:rate_limited, retry_delay(response)}}

  defp decode_response({:ok, %{status: 400, body: body}}), do: {:error, bad_request(body)}

  defp decode_response({:ok, %{status: status}}) do
    reason =
      case status do
        404 -> :category_unavailable
        410 -> :cursor_expired
        422 -> :unsupported_version
        status when status >= 500 -> :unavailable
        _other -> :unexpected_status
      end

    {:error, reason}
  end

  defp bad_request(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, %{"error" => %{"code" => "invalid_version"}}} -> :invalid_version
      {:ok, %{"error" => %{"code" => "invalid_cursor"}}} -> :invalid_cursor
      {:ok, %{"error" => %{"code" => "cursor_mismatch"}}} -> :cursor_mismatch
      _ -> :invalid_query
    end
  end

  defp bad_request(_body), do: :invalid_query

  defp retry_delay(response) do
    with [value] <- Req.Response.get_header(response, "retry-after"),
         true <- byte_size(value) <= 128,
         delay when is_integer(delay) and delay >= 0 <- Req.Response.get_retry_after(response) do
      min(delay, 86_400_000)
    else
      _ -> 60_000
    end
  rescue
    _ -> 60_000
  end
end
