defmodule Vxpipe.MCP.Connections do
  @moduledoc """
  Opens, reuses, and retires supervised MCP sessions.

  Supply the owner option to place sessions under a host-owned DynamicSupervisor.
  Its exact local PID scopes reuse and lookup; credential identity stays unchanged.
  Omitting ownership retains the legacy shared pool while consumers migrate.
  Invalid explicit ownership never falls back to that pool.
  """

  alias Vxpipe.MCP.{
    ClientOptions,
    Connection,
    ConnectionKey,
    ConnectionNames,
    CredentialLeases,
    ExMCPRuntime,
    IntegrationSupervisor,
    RuntimeAuthProvider,
    SessionStartup,
    Telemetry
  }

  @connection_supervisor Vxpipe.MCP.ConnectionSupervisor
  @protocol_version "2025-11-25"
  @startup_timeout 5_000

  @type error ::
          ClientOptions.error()
          | :connection_failed
          | :credential_revoked
          | :invalid_owner
          | :incompatible_connection
          | :not_ready
          | {:unsupported_protocol_version, String.t() | nil}

  @spec open(ConnectionKey.t(), keyword(), keyword()) :: {:ok, Connection.t()} | {:error, error()}
  def open(%ConnectionKey{} = key, config, opts \\ []) when is_list(config),
    do: report_open(key, config, opts, &ClientOptions.build/1)

  @doc "Opens plaintext only for an isolated loopback fixture."
  @spec open_loopback_test(ConnectionKey.t(), keyword(), keyword()) ::
          {:ok, Connection.t()} | {:error, error()}
  def open_loopback_test(%ConnectionKey{} = key, config, opts \\ []) when is_list(config),
    do: report_open(key, config, opts, &ClientOptions.build_loopback_test/1)

  defp report_open(key, config, opts, builder) do
    started_at = Telemetry.started_at()

    {result, outcome} =
      if CredentialLeases.revoked?(key) do
        {{:error, :credential_revoked}, :failed}
      else
        key |> open_connection(config, opts, builder) |> reject_revoked_connection(key)
      end

    Telemetry.connection_stop(
      started_at,
      :open,
      outcome,
      ConnectionNames.count(),
      result_client(result)
    )

    result
  end

  @doc "Revokes one local credential generation across every session owner."
  @spec revoke(ConnectionKey.t()) :: :ok
  def revoke(%ConnectionKey{} = key) do
    :ok = CredentialLeases.revoke(key)

    Enum.each(ConnectionNames.sessions(key), fn {parent, owner} ->
      retire_session(parent, owner, nil)
    end)
  end

  @spec lookup(ConnectionKey.t(), keyword()) :: {:ok, Connection.t()} | :error
  def lookup(%ConnectionKey{} = key, opts \\ []) do
    with {:ok, context} <- owner_context(opts),
         {:ok, connection} <- lookup_session(key, context),
         {:ok, runtime} <-
           ConnectionNames.runtime(key, context.scope, Connection.owner(connection)),
         :ok <- ensure_ready(connection, runtime) do
      {:ok, connection}
    else
      _invalid -> :error
    end
  catch
    :exit, _reason -> :error
  end

  @doc "Checks exact ownership and live registration before accepting a provider handle."
  @spec owned_by?(Connection.t(), GenServer.server()) :: boolean()
  def owned_by?(%Connection{} = connection, owner) do
    case lookup(Connection.key(connection), owner: owner) do
      {:ok, ^connection} -> true
      _foreign_or_retired -> false
    end
  end

  @spec close(Connection.t() | ConnectionKey.t()) :: :ok
  def close(%Connection{} = connection) do
    retire_session(
      Connection.session_owner(connection),
      Connection.owner(connection),
      Connection.client(connection)
    )
  end

  # Key-close is legacy; independently owned sessions require their exact handle.
  def close(%ConnectionKey{} = key) do
    retire_session(
      Process.whereis(@connection_supervisor),
      lookup_pid(:owner, key, nil),
      lookup_pid(:client, key, nil)
    )
  end

  defp retire_session(parent, owner, client) do
    started_at = Telemetry.started_at()
    outcome = if parent && owner, do: close_owner(parent, owner), else: :absent
    Telemetry.connection_stop(started_at, :close, outcome, ConnectionNames.count(), client)
    :ok
  end

  defp open_connection(key, config, opts, builder) do
    with {:ok, deadline} <- startup_deadline(opts),
         {:ok, context} <- owner_context(opts),
         {:ok, options} <- builder.(config) do
      runtime = Keyword.get(opts, :runtime, ExMCPRuntime)

      options =
        options
        |> Keyword.merge(Keyword.get(opts, :runtime_options, []))
        |> Enum.uniq_by(fn {key, _value} -> key end)

      context =
        Map.merge(context, %{
          runtime: runtime,
          deadline: deadline,
          client_options: options,
          policy: policy(runtime, options)
        })

      case lookup_session(key, context) do
        {:ok, connection} -> reuse_connection(connection, context)
        :error -> start_connection(key, context)
      end
    else
      {:error, _reason} = error -> {error, :failed}
    end
  end

  defp startup_deadline(opts) do
    now = System.monotonic_time(:millisecond)
    deadline = Keyword.get(opts, :deadline, now + @startup_timeout)

    if is_integer(deadline) and deadline > now,
      do: {:ok, deadline},
      else: {:error, :connection_failed}
  end

  defp owner_context(opts) do
    case Keyword.fetch(opts, :owner) do
      {:ok, owner} ->
        with {:ok, pid} <- resolve_owner(owner), do: {:ok, %{parent: pid, scope: pid}}

      :error ->
        with {:ok, pid} <- resolve_owner(@connection_supervisor),
             do: {:ok, %{parent: pid, scope: nil}}
    end
  end

  defp resolve_owner(owner) do
    case GenServer.whereis(owner) do
      pid when is_pid(pid) and node(pid) == node() ->
        if Process.alive?(pid), do: {:ok, pid}, else: {:error, :invalid_owner}

      _invalid ->
        {:error, :invalid_owner}
    end
  rescue
    ArgumentError -> {:error, :invalid_owner}
  end

  defp lookup_session(key, context) do
    with {:ok, owner} <- ConnectionNames.lookup(:owner, key, context.scope),
         {:ok, client} <- ConnectionNames.client(key, context.scope, owner) do
      {:ok, Connection.new(key, owner, client, context.parent)}
    else
      :error -> :error
    end
  end

  defp policy(runtime, options) do
    effective = options |> Keyword.drop([:name, :transport_supervisor]) |> Map.new()
    :crypto.hash(:sha256, :erlang.term_to_binary({runtime, effective}, [:deterministic]))
  end

  defp reuse_connection(connection, context) do
    with :ok <- compatible_policy(connection, context),
         :ok <- authorize_reuse(context.client_options),
         :ok <- ensure_ready(connection, context.runtime) do
      {{:ok, connection}, :reused}
    else
      {:error, _reason} = error -> {error, :failed}
    end
  catch
    :exit, _reason -> {{:error, :connection_failed}, :failed}
  end

  defp compatible_policy(_connection, %{scope: nil}), do: :ok

  defp compatible_policy(connection, context) do
    if ConnectionNames.policy(
         Connection.key(connection),
         context.scope,
         Connection.owner(connection)
       ) ==
         {:ok, context.policy},
       do: :ok,
       else: {:error, :incompatible_connection}
  end

  defp authorize_reuse(client_options) do
    case Keyword.get(client_options, :auth_provider) do
      {RuntimeAuthProvider, state} ->
        {:ok, _headers, ^state} = RuntimeAuthProvider.get_headers(state)
        :ok

      nil ->
        :ok
    end
  catch
    :exit, :mcp_credentials_unavailable -> {:error, :connection_failed}
  end

  defp reject_revoked_connection({{:ok, connection}, outcome}, key) do
    if CredentialLeases.revoked?(key) do
      :ok = close(connection)
      {{:error, :credential_revoked}, :failed}
    else
      {{:ok, connection}, outcome}
    end
  end

  defp reject_revoked_connection(result, _key), do: result

  defp start_connection(key, context) do
    case start_integration(key, context) do
      {:ok, owner, :started} ->
        result = finish_start(key, owner, context)
        if match?({:error, _}, result), do: close_owner(context.parent, owner)
        classify_open(result)

      {:ok, _owner, :existing} ->
        case lookup_session(key, context) do
          {:ok, connection} -> reuse_connection(connection, context)
          :error -> {{:error, :connection_failed}, :failed}
        end

      {:error, _reason} ->
        {{:error, :connection_failed}, :failed}
    end
  end

  defp finish_start(key, owner, context) do
    with {:ok, connection} <- lookup_session(key, context),
         ^owner <- Connection.owner(connection),
         :ok <- ensure_ready(connection, context.runtime) do
      {:ok, connection}
    else
      {:error, _reason} = error -> error
      _failure -> {:error, :connection_failed}
    end
  catch
    :exit, _reason -> {:error, :connection_failed}
  end

  defp start_integration(key, context) do
    child =
      {IntegrationSupervisor,
       key: key,
       runtime: context.runtime,
       client_options: context.client_options,
       parent: context.parent,
       caller: self(),
       deadline: context.deadline,
       scope: context.scope,
       policy: context.policy}

    task = Task.async(fn -> start_child(context.parent, child) end)
    remaining = max(context.deadline - System.monotonic_time(:millisecond), 0)

    case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _failed -> {:error, :connection_failed}
    end
  catch
    :exit, _reason -> {:error, :connection_failed}
  end

  defp start_child(parent, child) do
    case DynamicSupervisor.start_child(parent, child) do
      {:ok, owner} -> {:ok, owner, :started}
      {:error, {:already_started, owner}} -> {:ok, owner, :existing}
      {:error, _reason} -> {:error, :connection_failed}
    end
  catch
    :exit, _reason -> {:error, :connection_failed}
  end

  defp ensure_ready(connection, runtime) do
    case runtime.status(Connection.client(connection)) do
      {:ok, %{connection_status: :ready, protocol_version: @protocol_version}} ->
        SessionStartup.ready(Connection.owner(connection))

      {:ok, %{protocol_version: version}} ->
        {:error, {:unsupported_protocol_version, version}}

      {:ok, _status} ->
        {:error, :not_ready}

      {:error, _reason} ->
        {:error, :connection_failed}
    end
  end

  defp classify_open({:ok, %Connection{}} = result), do: {result, :opened}
  defp classify_open({:error, _reason} = result), do: {result, :failed}
  defp result_client({:ok, connection}), do: Connection.client(connection)
  defp result_client({:error, _reason}), do: nil

  defp lookup_pid(role, key, scope) do
    case ConnectionNames.lookup(role, key, scope) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  defp close_owner(parent, owner) do
    case DynamicSupervisor.terminate_child(parent, owner) do
      :ok -> :closed
      {:error, :not_found} -> :absent
    end
  catch
    :exit, _reason -> :absent
  end
end
