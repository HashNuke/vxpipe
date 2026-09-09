defmodule Vxpipe.MCP.ClientOptions do
  @moduledoc """
  Builds the fixed ExMCP client profile owned by Vxpipe.

  Broader protocol and retry support in ExMCP is intentionally not inherited.
  """

  @protocol_version "2025-11-25"

  @type error :: :endpoint_required | :https_required | :invalid_endpoint

  @spec build(keyword()) :: {:ok, keyword()} | {:error, error()}
  def build(config) when is_list(config) do
    with {:ok, endpoint} <- fetch_endpoint(config),
         :ok <- validate_endpoint(endpoint) do
      {:ok, options(endpoint, config)}
    end
  end

  defp fetch_endpoint(config) do
    case Keyword.fetch(config, :endpoint) do
      {:ok, endpoint} -> {:ok, endpoint}
      :error -> {:error, :endpoint_required}
    end
  end

  defp validate_endpoint(endpoint) when is_binary(endpoint) do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> :ok
      {:ok, %URI{scheme: scheme}} when scheme != "https" -> {:error, :https_required}
      _invalid -> {:error, :invalid_endpoint}
    end
  end

  defp validate_endpoint(_endpoint), do: {:error, :invalid_endpoint}

  defp options(endpoint, config) do
    [
      transport: :http,
      url: endpoint,
      headers: Keyword.get(config, :headers, []),
      protocol_mode: :legacy_only,
      protocol_version: @protocol_version,
      retry_policy: [],
      reconnect: true,
      use_sse: true
    ]
  end
end
