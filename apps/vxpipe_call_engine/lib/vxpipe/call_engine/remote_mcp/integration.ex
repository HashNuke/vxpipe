defmodule Vxpipe.CallEngine.RemoteMCP.Integration do
  @moduledoc """
  One validated configured integration record and its complete discovered catalog.

  Private client configuration stays here and must never be copied into a call plan.
  """

  alias Vxpipe.MCP.Catalog

  @derive {Inspect, except: [:client_config]}
  @enforce_keys [
    :integration_id,
    :configuration_generation,
    :credential_generation,
    :catalog_generation,
    :catalog,
    :allowed_tools,
    :client_config,
    :invocation_deadline_ms,
    :maximum_result_bytes
  ]
  defstruct @enforce_keys

  @maximum_identifier_bytes 128
  @maximum_deadline_ms 300_000
  @maximum_result_bytes 1_048_576

  @type t :: %__MODULE__{
          integration_id: String.t(),
          configuration_generation: String.t(),
          credential_generation: String.t(),
          catalog_generation: String.t(),
          catalog: Catalog.t(),
          allowed_tools: MapSet.t(String.t()),
          client_config: keyword(),
          invocation_deadline_ms: pos_integer(),
          maximum_result_bytes: pos_integer()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_integration}
  def new(options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         {:ok, integration_id} <- identifier(options, :integration_id),
         {:ok, configuration_generation} <- identifier(options, :configuration_generation),
         {:ok, credential_generation} <- identifier(options, :credential_generation),
         {:ok, catalog_generation} <- identifier(options, :catalog_generation),
         %Catalog{} = catalog <- Keyword.get(options, :catalog),
         {:ok, allowed_tools} <- allowed_tools(Keyword.get(options, :allowed_tools), catalog),
         client_config when is_list(client_config) <- Keyword.get(options, :client_config),
         {:ok, invocation_deadline_ms} <- invocation_deadline(options),
         {:ok, maximum_result_bytes} <- result_limit(options) do
      {:ok,
       %__MODULE__{
         integration_id: integration_id,
         configuration_generation: configuration_generation,
         credential_generation: credential_generation,
         catalog_generation: catalog_generation,
         catalog: catalog,
         allowed_tools: allowed_tools,
         client_config: client_config,
         invocation_deadline_ms: invocation_deadline_ms,
         maximum_result_bytes: maximum_result_bytes
       }}
    else
      _invalid -> {:error, :invalid_integration}
    end
  end

  defp validate_options(options) do
    Keyword.validate(options, [
      :integration_id,
      :configuration_generation,
      :credential_generation,
      :catalog_generation,
      :catalog,
      :allowed_tools,
      :client_config,
      :invocation_deadline_ms,
      :maximum_result_bytes
    ])
  end

  defp identifier(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) in 1..@maximum_identifier_bytes ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_integration}
    end
  end

  defp allowed_tools(tools, catalog) when is_list(tools) and tools != [] do
    unique = Enum.uniq(tools)

    if length(unique) == length(tools) and Enum.all?(tools, &available_tool?(&1, catalog)) do
      {:ok, MapSet.new(tools)}
    else
      {:error, :invalid_integration}
    end
  end

  defp allowed_tools(_tools, _catalog), do: {:error, :invalid_integration}

  defp available_tool?(name, catalog) when is_binary(name) do
    match?({:ok, _tool}, Catalog.fetch(catalog, name))
  end

  defp available_tool?(_name, _catalog), do: false

  defp invocation_deadline(options) do
    case Keyword.get(options, :invocation_deadline_ms, 30_000) do
      value when is_integer(value) and value in 1..@maximum_deadline_ms -> {:ok, value}
      _invalid -> {:error, :invalid_integration}
    end
  end

  defp result_limit(options) do
    case Keyword.get(options, :maximum_result_bytes, @maximum_result_bytes) do
      value when is_integer(value) and value in 1..@maximum_result_bytes -> {:ok, value}
      _invalid -> {:error, :invalid_integration}
    end
  end
end
