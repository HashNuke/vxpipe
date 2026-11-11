defmodule Vxpipe.Persistence.OAuth.ClientMetadata do
  @moduledoc "Bounded, credentialless CIMD retrieval through ExMCP's public-address HTTP boundary."
  alias ExMCP.Authorization.MetadataFetcher
  alias Vxpipe.Identity.OAuth.Profile

  def fetch(identifier) do
    options = Application.get_env(:vxpipe_persistence, :oauth_client_metadata, [])

    fetch_options =
      options
      |> Keyword.take([:dns_resolver, :http_client])
      |> Keyword.merge(
        max_redirects: 0,
        max_response_bytes: 65_536,
        max_aggregate_bytes: 65_536,
        dns_timeout_ms: 1_000,
        connect_timeout_ms: 2_000,
        request_timeout_ms: 5_000,
        allow_insecure_loopback: false
      )

    with true <- Profile.metadata_url?(identifier),
         {:ok, %{status: 200, body: body, headers: headers}} <-
           MetadataFetcher.fetch(identifier, fetch_options),
         true <- json?(headers),
         {:ok, document} <- JSON.decode(body),
         {:ok, metadata} <- Profile.client_metadata(document, identifier) do
      {:ok, metadata, DateTime.add(DateTime.utc_now(), lifetime(headers, options))}
    else
      _ -> {:error, :invalid_client}
    end
  end

  defp json?(headers) do
    headers |> header("content-type") |> String.split(";") |> hd() |> String.trim() ==
      "application/json"
  end

  defp lifetime(headers, options) do
    directives =
      headers
      |> header("cache-control")
      |> String.downcase()
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    maximum = Keyword.get(options, :max_cache_seconds, 3_600)
    default = Keyword.get(options, :default_cache_seconds, 300)
    age = headers |> header("age") |> seconds(0)

    if Enum.any?(directives, &(&1 in ["no-store", "no-cache"])) do
      0
    else
      max_age =
        Enum.find_value(directives, default, fn
          "max-age=" <> value -> seconds(String.trim(value, "\""), 0)
          _ -> nil
        end)

      max(0, min(max_age - age, maximum))
    end
  end

  defp header(headers, name),
    do:
      headers
      |> Enum.filter(fn {key, _} -> String.downcase(key) == name end)
      |> Enum.map_join(",", &elem(&1, 1))

  defp seconds(value, default) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> default
    end
  end
end
