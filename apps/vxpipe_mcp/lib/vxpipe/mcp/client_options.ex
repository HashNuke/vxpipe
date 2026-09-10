defmodule Vxpipe.MCP.ClientOptions do
  @moduledoc """
  Builds the fixed ExMCP client profile owned by Vxpipe.

  Broader protocol and retry support in ExMCP is intentionally not inherited.
  """

  alias Vxpipe.MCP.TransportOptions

  @protocol_version "2025-11-25"

  @type error ::
          :endpoint_required
          | :https_required
          | :invalid_endpoint
          | :invalid_reconnect
          | :loopback_required
          | TransportOptions.error()

  @spec build(keyword()) :: {:ok, keyword()} | {:error, error()}
  def build(config) when is_list(config) do
    with {:ok, endpoint} <- fetch_endpoint(config),
         :ok <- validate_production_endpoint(endpoint),
         {:ok, transport_options} <- TransportOptions.build(config) do
      {:ok, options(endpoint, config, transport_options, true)}
    end
  end

  @doc """
  Builds an isolated plaintext profile for loopback integration fixtures.

  Production configuration cannot select this profile through an option.
  """
  @spec build_loopback_test(keyword()) :: {:ok, keyword()} | {:error, error()}
  def build_loopback_test(config) when is_list(config) do
    with {:ok, endpoint} <- fetch_endpoint(config),
         :ok <- validate_loopback_endpoint(endpoint),
         {:ok, reconnect?} <- loopback_reconnect(config),
         {:ok, transport_options} <- TransportOptions.build(config) do
      {:ok, options(endpoint, config, transport_options, reconnect?)}
    end
  end

  defp fetch_endpoint(config) do
    case Keyword.fetch(config, :endpoint) do
      {:ok, endpoint} -> {:ok, endpoint}
      :error -> {:error, :endpoint_required}
    end
  end

  defp validate_production_endpoint(endpoint) when is_binary(endpoint) do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil, fragment: nil}}
      when is_binary(host) and host != "" ->
        :ok

      {:ok, %URI{scheme: scheme}} when scheme != "https" ->
        {:error, :https_required}

      _invalid ->
        {:error, :invalid_endpoint}
    end
  end

  defp validate_production_endpoint(_endpoint), do: {:error, :invalid_endpoint}

  defp validate_loopback_endpoint(endpoint) when is_binary(endpoint) do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: "http", host: host, userinfo: nil, fragment: nil}}
      when is_binary(host) ->
        if loopback_host?(host), do: :ok, else: {:error, :loopback_required}

      _invalid ->
        {:error, :loopback_required}
    end
  end

  defp validate_loopback_endpoint(_endpoint), do: {:error, :loopback_required}

  defp loopback_reconnect(config) do
    case Keyword.get(config, :reconnect, false) do
      reconnect? when is_boolean(reconnect?) -> {:ok, reconnect?}
      _invalid -> {:error, :invalid_reconnect}
    end
  end

  defp loopback_host?(host) do
    normalized = String.downcase(host)

    case :inet.parse_address(String.to_charlist(normalized)) do
      {:ok, {127, _b, _c, _d}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      _other -> normalized == "localhost"
    end
  end

  defp options(endpoint, config, transport_options, reconnect?) do
    base = [
      transport: :http,
      url: endpoint,
      headers: Keyword.get(config, :headers, []),
      security: endpoint_security(endpoint),
      allowed_private_hosts: Keyword.get(config, :allowed_private_hosts, []),
      protocol_mode: :legacy_only,
      protocol_version: @protocol_version,
      retry_policy: [],
      reconnect: reconnect?,
      use_sse: true
    ]

    Keyword.merge(base, transport_options)
  end

  defp endpoint_security(endpoint) do
    {:ok, origin} = ExMCP.Security.TokenHandler.extract_origin(endpoint)
    %{trusted_origins: [origin], trusted_hosts: []}
  end
end
