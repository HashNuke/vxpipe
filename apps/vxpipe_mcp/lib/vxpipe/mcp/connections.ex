defmodule Vxpipe.MCP.Connections do
  @moduledoc """
  Opens, reuses, and retires supervised MCP sessions.

  Supply the required owner option to place sessions under a host-owned DynamicSupervisor.
  Its exact local PID scopes reuse and lookup; credential identity stays unchanged.
  Missing or invalid ownership is rejected. There is no global session pool.
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
    SessionLifecycle,
    SessionOperation,
    SessionRetirement,
    Telemetry
  }

  @protocol_version "2025-11-25"
  @startup_timeout 5_000

  @type close_result :: :ok | {:error, :cleanup_incomplete}

  @type error ::
          ClientOptions.error()
          | :connection_failed
          | :cleanup_incomplete
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
  @spec revoke(ConnectionKey.t()) :: close_result()
  def revoke(%ConnectionKey{} = key) do
    :ok = CredentialLeases.revoke(key)

    SessionRetirement.close_owners(key, ConnectionNames.sessions(key))
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

  @spec close(Connection.t()) :: close_result()
  def close(%Connection{} = connection) do
    close_all([connection])
  end

  @doc "Fences all exact sessions before cleanup, sharing one absolute grace deadline."
  @spec close_all([Connection.t()], keyword()) :: close_result()
  def close_all(connections, opts \\ []) do
    SessionRetirement.close_all(connections, opts)
  end

  @doc """
  Rolls back selected keys in an exact owner after its opening work has stopped.

  Unlike handle close, this snapshots current sessions, including unready ones.
  Use only for the owner's startup rollback, never for a delayed incarnation close.
  The entire batch shares one cleanup deadline.
  """
  @spec close_owned([ConnectionKey.t()], pid(), keyword()) :: close_result()
  def close_owned(keys, owner, opts \\ []) when is_pid(owner) do
    SessionRetirement.close_owned(keys, owner, opts)
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
        {:error, :invalid_owner}
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
         :ok <-
           SessionOperation.run(Connection.owner(connection), context.deadline, fn ->
             with :ok <- authorize_reuse(context.client_options),
                  do: ready_status(connection, context.runtime)
           end) do
      {{:ok, connection}, :reused}
    else
      {:error, _reason} = error -> {error, :failed}
    end
  catch
    :exit, _reason -> {{:error, :connection_failed}, :failed}
  end

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
        result =
          case finish_start(key, owner, context) do
            {:error, _reason} = failure -> abandon_start(key, owner, context, failure)
            success -> success
          end

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

  defp abandon_start(key, owner, context, failure) do
    cleanup =
      case SessionLifecycle.abandon_start(owner) do
        :retained ->
          :ok

        :retire ->
          SessionRetirement.close_owners(key, [{context.parent, owner}],
            deadline: context.deadline
          )

        incomplete ->
          incomplete
      end

    if cleanup == :ok, do: failure, else: cleanup
  end

  defp finish_start(key, owner, context) do
    with {:ok, connection} <- lookup_session(key, context),
         ^owner <- Connection.owner(connection),
         :ok <-
           SessionOperation.run(owner, context.deadline, fn ->
             ready_status(connection, context.runtime)
           end) do
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
    with :ok <- ready_status(connection, runtime),
         do: SessionLifecycle.ready(Connection.owner(connection))
  end

  defp ready_status(connection, runtime) do
    case runtime.status(Connection.client(connection)) do
      {:ok, %{connection_status: :ready, protocol_version: @protocol_version}} ->
        :ok

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
end
