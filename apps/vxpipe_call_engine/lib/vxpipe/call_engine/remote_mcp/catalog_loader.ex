defmodule Vxpipe.CallEngine.RemoteMCP.CatalogLoader do
  @moduledoc """
  Loads one complete discovered catalog for validated scoped integration configuration.
  """

  alias Vxpipe.CallEngine.RemoteMCP.{ConfiguredIntegration, Integration}
  alias Vxpipe.MCP.{Connection, Connections, Discovery, ExMCPClient}

  @type error ::
          :connection_failed
          | :cleanup_incomplete
          | :credential_revoked
          | :invalid_configuration
          | :invalid_discovered_catalog
          | Discovery.error()

  @spec load(ConfiguredIntegration.t(), keyword()) ::
          {:ok, Integration.t()} | {:error, error()}
  def load(configured, options \\ [])

  def load(%ConfiguredIntegration{} = configured, options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         {:ok, connection_provider} <-
           module_with_function(Keyword.get(options, :connection_provider, Connections), :open, 3),
         {:ok, protocol} <-
           module_with_function(Keyword.get(options, :protocol, ExMCPClient), :list_tools, 3),
         {:ok, owner} <- start_owner() do
      result = run(configured, connection_provider, protocol, owner)
      cleanup = Connections.close_owned([configured.connection_key], owner)
      stopped = stop_owner(owner)

      if cleanup == :ok and stopped == :ok,
        do: result,
        else: {:error, :cleanup_incomplete}
    else
      {:error, :credential_revoked} = error ->
        error

      {:error, reason} when reason in [:invalid_configuration, :invalid_discovered_catalog] ->
        {:error, reason}

      {:error, reason} when reason in [:connection_failed, :invalid_connection] ->
        {:error, :connection_failed}

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_configuration}
    end
  end

  def load(%ConfiguredIntegration{}, _options), do: {:error, :invalid_configuration}

  defp start_owner do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {__MODULE__, make_ref()}}}
    DynamicSupervisor.start_link(strategy: :one_for_one, name: name)
  end

  defp run(configured, provider, protocol, owner) do
    deadline = System.monotonic_time(:millisecond) + configured.discovery_deadline_ms
    task = Task.async(fn -> load_owned(configured, provider, protocol, owner, deadline) end)

    try do
      case Task.yield(task, remaining(deadline)) do
        {:ok, result} ->
          if remaining(deadline) > 0, do: result, else: {:error, :discovery_timed_out}

        nil ->
          {:error, :discovery_timed_out}

        _failed ->
          {:error, :connection_failed}
      end
    after
      Task.shutdown(task, :brutal_kill)
      flush_exit(task.pid)
    end
  end

  defp load_owned(configured, provider, protocol, owner, deadline) do
    with {:ok, connection} <- open(configured, provider, owner, deadline),
         {:ok, catalog} <- discover(configured, connection, protocol, deadline),
         do: build_integration(configured, catalog)
  rescue
    _exception -> {:error, :connection_failed}
  catch
    _kind, _reason -> {:error, :connection_failed}
  end

  defp stop_owner(owner) do
    monitor = Process.monitor(owner)

    result =
      try do
        Supervisor.stop(owner, :normal, 1_000)
      catch
        :exit, _reason ->
          Process.unlink(owner)
          Process.exit(owner, :kill)
          {:error, :cleanup_incomplete}
      end

    receive do
      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        flush_exit(owner)
        result
    after
      1_000 ->
        Process.demonitor(monitor, [:flush])
        {:error, :cleanup_incomplete}
    end
  end

  defp flush_exit(pid) do
    receive do: ({:EXIT, ^pid, _reason} -> :ok), after: (0 -> :ok)
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp validate_options(options) do
    case Keyword.validate(options, [:connection_provider, :protocol]) do
      {:ok, options} -> {:ok, options}
      {:error, _reason} -> {:error, :invalid_configuration}
    end
  end

  defp module_with_function(module, function, arity) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, arity) do
      {:ok, module}
    else
      {:error, :invalid_configuration}
    end
  end

  defp module_with_function(_module, _function, _arity), do: {:error, :invalid_configuration}

  defp open(configured, connection_provider, owner, deadline) do
    config = enforce_response_limits(configured)

    case connection_provider.open(configured.connection_key, config,
           owner: owner,
           deadline: deadline
         ) do
      {:ok, %Connection{} = connection} ->
        if Connection.key(connection) == configured.connection_key and
             Connections.owned_by?(connection, owner) do
          {:ok, connection}
        else
          {:error, :connection_failed}
        end

      {:error, :credential_revoked} = error ->
        error

      _failure ->
        {:error, :connection_failed}
    end
  end

  defp enforce_response_limits(configured) do
    limits =
      configured.client_config
      |> Keyword.get(:limits, [])
      |> Keyword.merge(
        max_response_bytes: configured.maximum_result_bytes,
        max_stream_buffer_bytes: configured.maximum_result_bytes
      )

    Keyword.put(configured.client_config, :limits, limits)
  end

  defp discover(configured, connection, protocol, deadline) do
    if remaining(deadline) > 0 do
      Discovery.discover(Connection.client(connection),
        protocol: protocol,
        deadline_ms: remaining(deadline),
        max_pages: configured.maximum_discovery_pages,
        max_decoded_bytes: configured.maximum_discovery_bytes
      )
    else
      {:error, :discovery_timed_out}
    end
  end

  defp build_integration(configured, catalog) do
    key = configured.connection_key

    case Integration.new(
           integration_id: key.integration_id,
           configuration_generation: configured.configuration_generation,
           credential_generation: key.credential_generation,
           catalog_generation: configured.catalog_generation,
           catalog: catalog,
           allowed_tools: configured.allowed_tools,
           client_config: configured.client_config,
           invocation_deadline_ms: configured.invocation_deadline_ms,
           maximum_result_bytes: configured.maximum_result_bytes
         ) do
      {:ok, integration} -> {:ok, integration}
      {:error, :invalid_integration} -> {:error, :invalid_discovered_catalog}
    end
  end
end
