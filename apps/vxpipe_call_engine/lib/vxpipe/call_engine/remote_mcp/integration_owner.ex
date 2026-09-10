defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwner do
  @moduledoc """
  Owns one agent activation's authorized runtime access to its pinned MCP tools.

  Private integration configuration is used while opening scoped protocol clients and is not
  retained in this process's state or returned to callers.
  """

  use GenServer

  alias Vxpipe.CallEngine.RemoteMCP.{Executor, Integration, IntegrationCatalog, RuntimeBinding}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ExMCPClient}

  @binding_timeout_ms 5_000

  @derive {Inspect, only: [:binding_count]}
  @enforce_keys [:bindings, :binding_count]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bindings: %{String.t() => RuntimeBinding.t()},
          binding_count: non_neg_integer()
        }

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec execute(GenServer.server(), String.t(), map()) ::
          {:ok, map()}
          | {:error,
             :invalid_arguments | :invalid_result | :tool_failed | :unknown | :unknown_tool}
  def execute(owner, local_name, arguments)
      when is_binary(local_name) and is_map(arguments) do
    with {:ok, binding} <- binding(owner, local_name) do
      Executor.execute(binding, arguments)
    end
  rescue
    _exception -> {:error, :tool_failed}
  catch
    :exit, _reason -> {:error, :tool_failed}
  end

  def execute(_owner, _local_name, _arguments), do: {:error, :invalid_arguments}

  @impl true
  def init(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :activation_id,
             :connection_provider,
             :integrations,
             :name,
             :protocol,
             :tools
           ]),
         activation_id when is_binary(activation_id) <- Keyword.get(options, :activation_id),
         true <- activation_id != "",
         %IntegrationCatalog{} = integrations <- Keyword.get(options, :integrations),
         tools when is_map(tools) <- Keyword.get(options, :tools),
         connection_provider when is_atom(connection_provider) <-
           Keyword.get(options, :connection_provider, Connections),
         true <-
           Code.ensure_loaded?(connection_provider) and
             function_exported?(connection_provider, :open, 2),
         protocol when is_atom(protocol) <- Keyword.get(options, :protocol, ExMCPClient),
         true <- Code.ensure_loaded?(protocol) and function_exported?(protocol, :call_tool, 4),
         {:ok, prepared} <- prepare(tools, integrations),
         {:ok, connections} <- open_connections(prepared, connection_provider),
         bindings <- runtime_bindings(prepared, connections, protocol) do
      {:ok, %__MODULE__{bindings: bindings, binding_count: map_size(bindings)}}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:binding, local_name}, _from, %__MODULE__{} = state) do
    case Map.fetch(state.bindings, local_name) do
      {:ok, binding} -> {:reply, {:ok, binding}, state}
      :error -> {:reply, {:error, :unknown_tool}, state}
    end
  end

  defp binding(owner, local_name) do
    GenServer.call(owner, {:binding, local_name}, @binding_timeout_ms)
  end

  defp prepare(tools, integrations) do
    Enum.reduce_while(tools, {:ok, []}, fn
      {name, %ToolBinding{name: name, type: :host}}, {:ok, prepared} ->
        {:cont, {:ok, prepared}}

      {name, %ToolBinding{name: name, type: :mcp, remote: remote}}, {:ok, prepared} ->
        with {:ok, integration} <- IntegrationCatalog.checkout(integrations, remote),
             {:ok, key} <- connection_key(remote) do
          entry = %{name: name, remote: remote, integration: integration, key: key}
          {:cont, {:ok, [entry | prepared]}}
        else
          _invalid -> {:halt, {:error, :invalid_configuration}}
        end

      _invalid, {:ok, _prepared} ->
        {:halt, {:error, :invalid_configuration}}
    end)
  end

  defp connection_key(%{scope: :application} = remote) do
    ConnectionKey.new(
      scope: :application,
      integration_id: remote.integration_id,
      credential_generation: remote.credential_generation
    )
  end

  defp connection_key(%{scope: {:tenant, tenant_id}} = remote) do
    ConnectionKey.new(
      scope: :tenant,
      tenant_id: tenant_id,
      integration_id: remote.integration_id,
      credential_generation: remote.credential_generation
    )
  end

  defp open_connections(prepared, connection_provider) do
    Enum.reduce_while(prepared, {:ok, %{}}, fn entry, {:ok, connections} ->
      case Map.fetch(connections, entry.key) do
        {:ok, _connection} ->
          {:cont, {:ok, connections}}

        :error ->
          case open_connection(entry, connection_provider) do
            {:ok, connection} ->
              {:cont, {:ok, Map.put(connections, entry.key, connection)}}

            {:error, _reason} ->
              {:halt, {:error, :invalid_configuration}}
          end
      end
    end)
  end

  defp open_connection(entry, connection_provider) do
    config = connection_config(entry.integration)

    case connection_provider.open(entry.key, config) do
      {:ok, %Connection{} = connection} ->
        if Connection.key(connection) == entry.key,
          do: {:ok, connection},
          else: {:error, :invalid_connection}

      _failure ->
        {:error, :connection_failed}
    end
  end

  defp connection_config(%Integration{} = integration) do
    enforced_limits = [
      max_response_bytes: integration.maximum_result_bytes,
      max_stream_buffer_bytes: integration.maximum_result_bytes
    ]

    limits =
      integration.client_config
      |> Keyword.get(:limits, [])
      |> Keyword.merge(enforced_limits)

    Keyword.put(integration.client_config, :limits, limits)
  end

  defp runtime_bindings(prepared, connections, protocol) do
    Map.new(prepared, fn entry ->
      binding = %RuntimeBinding{
        local_name: entry.name,
        resolved: entry.remote,
        catalog: entry.integration.catalog,
        connection: Map.fetch!(connections, entry.key),
        protocol: protocol
      }

      {entry.name, binding}
    end)
  end
end
