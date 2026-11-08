defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwner do
  @moduledoc """
  Owns one agent activation's authorized runtime access to its pinned MCP tools.

  Requires a host-owned session supervisor. Connection providers implement `open/3`
  and receive its exact PID in the owner option; foreign handles are rejected.
  Private integration configuration is used while opening scoped protocol clients and is not
  retained in this process's state or returned to callers.
  """

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RemoteMCP.{Executor, Integration, IntegrationCatalog, RuntimeBinding}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, CredentialLeases, ExMCPClient}

  @binding_timeout_ms 5_000

  @derive {Inspect, only: [:binding_count]}
  @enforce_keys [:bindings, :binding_count, :connection_monitors]
  defstruct @enforce_keys ++ [readiness_resource: nil]

  @type t :: %__MODULE__{
          bindings: %{String.t() => RuntimeBinding.t()},
          binding_count: non_neg_integer(),
          connection_monitors: %{reference() => Vxpipe.MCP.ConnectionKey.t()}
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

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(owner) do
    GenServer.call(owner, :readiness, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    with {:ok, options} <-
           Keyword.validate(options, [
             :activation_id,
             :connection_provider,
             :initialization,
             :integrations,
             :lifecycle_owner,
             :name,
             :participant_id,
             :protocol,
             :session_supervisor,
             :tools
           ]),
         activation_id when is_binary(activation_id) <- Keyword.get(options, :activation_id),
         true <- activation_id != "",
         participant_id when is_nil(participant_id) or is_binary(participant_id) <-
           Keyword.get(options, :participant_id),
         true <- participant_id != "",
         %IntegrationCatalog{} = integrations <- Keyword.get(options, :integrations),
         tools when is_map(tools) <- Keyword.get(options, :tools),
         session_supervisor when is_pid(session_supervisor) <-
           GenServer.whereis(Keyword.get(options, :session_supervisor)),
         connection_provider when is_atom(connection_provider) <-
           Keyword.get(options, :connection_provider, Connections),
         true <-
           Code.ensure_loaded?(connection_provider) and
             function_exported?(connection_provider, :open, 3),
         protocol when is_atom(protocol) <- Keyword.get(options, :protocol, ExMCPClient),
         true <- Code.ensure_loaded?(protocol) and function_exported?(protocol, :call_tool, 4),
         {:ok, prepared} <- prepare(tools, integrations),
         :ok <- acquire_credential_leases(prepared),
         {:ok, connections, connection_monitors} <-
           initialize_connections(prepared, connection_provider, session_supervisor, options),
         bindings <- runtime_bindings(prepared, connections, protocol) do
      {:ok,
       %__MODULE__{
         bindings: bindings,
         binding_count: map_size(bindings),
         connection_monitors: connection_monitors,
         readiness_resource: readiness_resource(participant_id, activation_id, tools, prepared)
       }}
    else
      {:error, :credential_revoked} -> {:stop, :credential_revoked}
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(:readiness, _from, %{readiness_resource: nil} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call(:readiness, _from, state) do
    {:reply, {:ok, state.readiness_resource, :ready}, state}
  end

  def handle_call({:binding, local_name}, _from, %__MODULE__{} = state) do
    case Map.fetch(state.bindings, local_name) do
      {:ok, binding} -> {:reply, {:ok, binding}, state}
      :error -> {:reply, {:error, :unknown_tool}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _pid, _reason}, %__MODULE__{} = state) do
    if Map.has_key?(state.connection_monitors, reference) do
      {:stop, :connection_lost, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:vxpipe_mcp_credential_revoked, %ConnectionKey{}}, state) do
    {:stop, :credential_revoked, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{bindings: bindings}) do
    # Graceful protocol cleanup is best effort. The activation-owned session
    # subtree still removes all clients/workers when this process is killed.
    bindings
    |> Map.values()
    |> Enum.map(& &1.connection)
    |> Enum.uniq()
    |> Connections.close_all()
  end

  defp binding(owner, local_name) do
    GenServer.call(owner, {:binding, local_name}, @binding_timeout_ms)
  end

  defp readiness_resource(nil, _activation_id, _tools, _prepared), do: nil

  defp readiness_resource(participant_id, activation_id, tools, prepared) do
    Resource.new(
      :remote_tools,
      {:participant, participant_id},
      __MODULE__,
      {activation_id, tools, prepared},
      binding: activation_id
    )
  end

  defp acquire_credential_leases(prepared) do
    prepared
    |> Enum.map(& &1.key)
    |> Enum.uniq()
    |> CredentialLeases.acquire()
  end

  defp prepare(tools, integrations) do
    Enum.reduce_while(tools, {:ok, []}, fn
      {name, %ToolBinding{name: name, type: type}}, {:ok, prepared}
      when type in [:host, :participant_transfer, :platform] ->
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

  defp initialize_connections(prepared, provider, sessions, options) do
    owner = Keyword.get(options, :lifecycle_owner)

    with {:ok, deadline, preparer} <- initialization_budget(options),
         true <- deadline > System.monotonic_time(:millisecond),
         owners <- Enum.uniq(Enum.filter([owner, preparer], &is_pid/1)),
         true <- Enum.all?(owners, &Process.alive?/1) do
      run_initialization(prepared, provider, sessions, deadline, owners)
    else
      _unavailable -> {:error, :invalid_configuration}
    end
  end

  defp initialization_budget(options) do
    case Keyword.get(options, :initialization) do
      nil ->
        {:ok, System.monotonic_time(:millisecond) + 5_000, nil}

      {preparer, deadline} when is_pid(preparer) and is_integer(deadline) ->
        owner = Keyword.fetch!(options, :lifecycle_owner)
        preparing? = Process.alive?(preparer)
        admission_deadline = System.monotonic_time(:millisecond) + 1_000

        admission_deadline =
          if preparing?, do: min(deadline, admission_deadline), else: admission_deadline

        owners = if preparing?, do: [owner, preparer], else: [owner]

        work = fn ->
          Vxpipe.CallEngine.RoomAuthority.Startup.mcp_initialization_budget(
            owner,
            Keyword.fetch!(options, :activation_id),
            preparer,
            deadline
          )
        end

        initialization_task(work, admission_deadline, Enum.uniq(owners))

      _invalid ->
        {:error, :invalid_configuration}
    end
  end

  defp run_initialization(prepared, provider, sessions, deadline, owners) do
    result =
      initialization_task(
        fn -> open_connections(prepared, provider, sessions, deadline) end,
        deadline,
        owners
      )

    with {:ok, connections} <- result,
         {:ok, connection_monitors} <- monitor_connections(connections) do
      {:ok, connections, connection_monitors}
    else
      _failure ->
        keys = Enum.map(prepared, & &1.key)
        cleanup_deadline = min(deadline, System.monotonic_time(:millisecond) + 1_000)
        _ = Connections.close_owned(keys, sessions, deadline: cleanup_deadline)
        {:error, :invalid_configuration}
    end
  end

  defp initialization_task(work, deadline, owners) do
    monitors = Map.new(owners, &{Process.monitor(&1), &1})

    task =
      Task.async(fn ->
        if System.monotonic_time(:millisecond) < deadline and Enum.all?(owners, &Process.alive?/1),
          do: work.(),
          else: {:error, :invalid_configuration}
      end)

    result =
      try do
        await_initialization(task, monitors, deadline)
      after
        Enum.each(monitors, fn {reference, _owner} -> Process.demonitor(reference, [:flush]) end)
        _ = Task.shutdown(task, :brutal_kill)
      end

    if System.monotonic_time(:millisecond) < deadline and Enum.all?(owners, &Process.alive?/1) do
      result
    else
      {:error, :invalid_configuration}
    end
  end

  defp await_initialization(%Task{ref: reference}, monitors, deadline) do
    receive do
      {^reference, result} ->
        result

      {:DOWN, ^reference, :process, _worker, _reason} ->
        {:error, :invalid_configuration}

      {:DOWN, owner_monitor, :process, _owner, _reason}
      when is_map_key(monitors, owner_monitor) ->
        {:error, :invalid_configuration}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :invalid_configuration}
    end
  end

  defp open_connections(prepared, connection_provider, session_supervisor, deadline) do
    Enum.reduce_while(prepared, {:ok, %{}}, fn entry, {:ok, connections} ->
      case Map.fetch(connections, entry.key) do
        {:ok, _connection} ->
          {:cont, {:ok, connections}}

        :error ->
          case open_connection(entry, connection_provider, session_supervisor, deadline) do
            {:ok, connection} ->
              {:cont, {:ok, Map.put(connections, entry.key, connection)}}

            {:error, _reason} ->
              {:halt, {:error, :invalid_configuration}}
          end
      end
    end)
  end

  defp open_connection(entry, connection_provider, session_supervisor, deadline) do
    config = connection_config(entry.integration)

    case connection_provider.open(entry.key, config,
           owner: session_supervisor,
           deadline: deadline
         ) do
      {:ok, %Connection{} = connection} ->
        if Connection.key(connection) == entry.key and
             Connections.owned_by?(connection, session_supervisor),
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

  defp monitor_connections(connections) do
    Enum.reduce_while(connections, {:ok, %{}}, fn {key, connection}, {:ok, monitors} ->
      case GenServer.whereis(Connection.client(connection)) do
        client when is_pid(client) ->
          reference = Process.monitor(client)
          {:cont, {:ok, Map.put(monitors, reference, key)}}

        nil ->
          {:halt, {:error, :connection_lost}}
      end
    end)
  end
end
