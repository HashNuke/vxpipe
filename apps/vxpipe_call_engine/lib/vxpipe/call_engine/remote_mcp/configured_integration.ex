defmodule Vxpipe.CallEngine.RemoteMCP.ConfiguredIntegration do
  @moduledoc """
  Validated private configuration used to discover one scoped MCP integration.

  This value is infrastructure configuration, not part of a resolved call plan.
  """

  alias Vxpipe.MCP.ConnectionKey

  @derive {Inspect, except: [:client_config]}
  @enforce_keys [
    :connection_key,
    :configuration_generation,
    :catalog_generation,
    :allowed_tools,
    :client_config,
    :invocation_deadline_ms,
    :maximum_result_bytes,
    :discovery_deadline_ms,
    :maximum_discovery_pages,
    :maximum_discovery_bytes
  ]
  defstruct @enforce_keys

  @maximum_identifier_bytes 128
  @maximum_deadline_ms 300_000
  @maximum_result_bytes 1_048_576
  @maximum_discovery_pages 100

  @type t :: %__MODULE__{
          connection_key: ConnectionKey.t(),
          configuration_generation: String.t(),
          catalog_generation: String.t(),
          allowed_tools: [String.t()],
          client_config: keyword(),
          invocation_deadline_ms: pos_integer(),
          maximum_result_bytes: pos_integer(),
          discovery_deadline_ms: pos_integer(),
          maximum_discovery_pages: pos_integer(),
          maximum_discovery_bytes: pos_integer()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configured_integration}
  def new(options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         {:ok, connection_key} <- connection_key(options),
         {:ok, configuration_generation} <- identifier(options, :configuration_generation),
         {:ok, catalog_generation} <- identifier(options, :catalog_generation),
         {:ok, allowed_tools} <- allowed_tools(Keyword.get(options, :allowed_tools)),
         {:ok, client_config} <- client_config(Keyword.get(options, :client_config)),
         {:ok, invocation_deadline_ms} <-
           bounded_positive(options, :invocation_deadline_ms, 30_000, @maximum_deadline_ms),
         {:ok, maximum_result_bytes} <-
           bounded_positive(
             options,
             :maximum_result_bytes,
             @maximum_result_bytes,
             @maximum_result_bytes
           ),
         {:ok, discovery_deadline_ms} <-
           bounded_positive(options, :discovery_deadline_ms, 5_000, @maximum_deadline_ms),
         {:ok, maximum_discovery_pages} <-
           bounded_positive(options, :maximum_discovery_pages, 20, @maximum_discovery_pages),
         {:ok, maximum_discovery_bytes} <-
           bounded_positive(
             options,
             :maximum_discovery_bytes,
             1_000_000,
             @maximum_result_bytes
           ) do
      {:ok,
       %__MODULE__{
         connection_key: connection_key,
         configuration_generation: configuration_generation,
         catalog_generation: catalog_generation,
         allowed_tools: allowed_tools,
         client_config: client_config,
         invocation_deadline_ms: invocation_deadline_ms,
         maximum_result_bytes: maximum_result_bytes,
         discovery_deadline_ms: discovery_deadline_ms,
         maximum_discovery_pages: maximum_discovery_pages,
         maximum_discovery_bytes: maximum_discovery_bytes
       }}
    else
      _invalid -> {:error, :invalid_configured_integration}
    end
  end

  def new(_options), do: {:error, :invalid_configured_integration}

  defp validate_options(options) do
    Keyword.validate(options, [
      :scope,
      :integration_id,
      :configuration_generation,
      :credential_generation,
      :catalog_generation,
      :allowed_tools,
      :client_config,
      :invocation_deadline_ms,
      :maximum_result_bytes,
      :discovery_deadline_ms,
      :maximum_discovery_pages,
      :maximum_discovery_bytes
    ])
  end

  defp connection_key(options) do
    base = [
      integration_id: Keyword.get(options, :integration_id),
      credential_generation: Keyword.get(options, :credential_generation)
    ]

    case Keyword.get(options, :scope) do
      :application -> ConnectionKey.new([scope: :application] ++ base)
      {:tenant, tenant_id} -> ConnectionKey.new([scope: :tenant, tenant_id: tenant_id] ++ base)
      _invalid -> {:error, :invalid_connection_key}
    end
  end

  defp identifier(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) in 1..@maximum_identifier_bytes ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_identifier}
    end
  end

  defp allowed_tools(tools) when is_list(tools) and tools != [] do
    if Enum.uniq(tools) == tools and Enum.all?(tools, &bounded_identifier?/1) do
      {:ok, tools}
    else
      {:error, :invalid_allowed_tools}
    end
  end

  defp allowed_tools(_tools), do: {:error, :invalid_allowed_tools}

  defp client_config(config) when is_list(config) do
    limits = Keyword.get(config, :limits, [])

    if Keyword.keyword?(config) and is_list(limits) and Keyword.keyword?(limits) do
      {:ok, config}
    else
      {:error, :invalid_client_config}
    end
  end

  defp client_config(_config), do: {:error, :invalid_client_config}

  defp bounded_positive(options, key, default, maximum) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value >= 1 and value <= maximum -> {:ok, value}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp bounded_identifier?(value) when is_binary(value),
    do: byte_size(value) in 1..@maximum_identifier_bytes

  defp bounded_identifier?(_value), do: false
end
