defmodule Vxpipe.CallEngine.VoiceCatalog.HTTP do
  @moduledoc "Bounded, non-retrying catalog reads with value-free failures."
  @maximum_bytes 2_097_152
  def get(url, headers, params, options) do
    request = [
      headers: [{"accept-encoding", "identity"} | headers],
      params: params,
      retry: false,
      redirect: false,
      raw: true,
      receive_timeout: 8_000,
      connect_options: [timeout: 3_000],
      into: &collect/2
    ]

    case Req.get(url, request ++ Keyword.take(options, [:plug])) do
      {:ok, response} -> decode(response)
      _ -> {:error, :voice_catalog_unavailable}
    end
  rescue
    _ -> {:error, :voice_catalog_unavailable}
  end

  defp collect({:data, data}, {request, response}) do
    if byte_size(response.body) + byte_size(data) <= @maximum_bytes do
      {:cont, {request, %{response | body: response.body <> data}}}
    else
      {:halt, {request, Req.Response.put_private(response, :catalog_too_large, true)}}
    end
  end

  defp decode(%{private: %{catalog_too_large: true}}),
    do: {:error, :invalid_voice_catalog_response}

  defp decode(%{status: 200, body: body})
       when is_binary(body) and byte_size(body) <= @maximum_bytes do
    case JSON.decode(body) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  defp decode(%{status: 404}), do: {:error, :voice_not_found}

  defp decode(%{status: status}) when status in [401, 403],
    do: {:error, :voice_catalog_credentials_rejected}

  defp decode(%{status: 429}), do: {:error, :voice_catalog_rate_limited}
  defp decode(_), do: {:error, :voice_catalog_unavailable}
end
