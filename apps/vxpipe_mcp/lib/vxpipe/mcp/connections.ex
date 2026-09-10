defmodule Vxpipe.MCP.Connections do
  @moduledoc """
  Opens, reuses, and retires supervised MCP sessions by resolved connection identity.

  A connection is returned only after its runtime reports `:ready` with the exact Vxpipe
  protocol revision.
  """

  alias Vxpipe.MCP.{
    ClientOptions,
    Connection,
    ConnectionKey,
    ConnectionNames,
    CredentialLeases,
    ExMCPRuntime,
    IntegrationSupervisor,
    Telemetry
  }

  @connection_supervisor Vxpipe.MCP.ConnectionSupervisor
  @protocol_version "2025-11-25"

  @type error ::
          ClientOptions.error()
          | :connection_failed
          | :credential_revoked
          | :not_ready
          | {:unsupported_protocol_version, String.t() | nil}

  @spec open(ConnectionKey.t(), keyword(), keyword()) ::
          {:ok, Connection.t()} | {:error, error()}
  def open(%ConnectionKey{} = key, config, opts \\ []) when is_list(config) do
    report_open(key, config, opts, &ClientOptions.build/1)
  end

  @doc """
  Opens a plaintext client only for an isolated loopback fixture.

  This separate entry cannot be selected through production integration configuration.
  """
  @spec open_loopback_test(ConnectionKey.t(), keyword(), keyword()) ::
          {:ok, Connection.t()} | {:error, error()}
  def open_loopback_test(%ConnectionKey{} = key, config, opts \\ [])
      when is_list(config) do
    report_open(key, config, opts, &ClientOptions.build_loopback_test/1)
  end

  defp report_open(key, config, opts, options_builder) do
    started_at = Telemetry.started_at()

    {result, outcome} =
      if CredentialLeases.revoked?(key) do
        {{:error, :credential_revoked}, :failed}
      else
        key
        |> open_connection(config, opts, options_builder)
        |> reject_revoked_connection(key)
      end

    Telemetry.connection_stop(
      started_at,
      :open,
      outcome,
      active_connection_count(),
      result_client(result)
    )

    result
  end

  @spec revoke(ConnectionKey.t()) :: :ok
  def revoke(%ConnectionKey{} = key) do
    :ok = CredentialLeases.revoke(key)
    close(key)
  end

  @spec lookup(ConnectionKey.t()) :: {:ok, Connection.t()} | :error
  def lookup(%ConnectionKey{} = key) do
    with {:ok, owner} <- ConnectionNames.lookup(:owner, key),
         {:ok, client} <- ConnectionNames.lookup(:client, key) do
      {:ok, Connection.new(key, owner, client)}
    else
      :error -> :error
    end
  end

  @spec close(Connection.t() | ConnectionKey.t()) :: :ok
  def close(%Connection{} = connection), do: close(Connection.key(connection))

  def close(%ConnectionKey{} = key) do
    started_at = Telemetry.started_at()
    client = lookup_client(key)

    outcome =
      case ConnectionNames.lookup(:owner, key) do
        {:ok, owner} -> close_owner(owner)
        :error -> :absent
      end

    Telemetry.connection_stop(
      started_at,
      :close,
      outcome,
      active_connection_count(),
      client
    )

    :ok
  end

  defp open_connection(key, config, opts, options_builder) do
    case lookup(key) do
      {:ok, connection} -> {{:ok, connection}, :reused}
      :error -> classify_open(start_connection(key, config, opts, options_builder))
    end
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

  defp start_connection(key, config, opts, options_builder) do
    runtime = Keyword.get(opts, :runtime, ExMCPRuntime)
    runtime_options = Keyword.get(opts, :runtime_options, [])

    with {:ok, client_options} <- options_builder.(config),
         {:ok, _owner} <-
           start_integration(key, runtime, client_options, runtime_options),
         {:ok, connection} <- lookup(key),
         :ok <- ensure_ready(connection, runtime) do
      {:ok, connection}
    else
      {:error, {:unsupported_protocol_version, _version}} = error ->
        close(key)
        error

      {:error, :not_ready} = error ->
        close(key)
        error

      {:error, reason} when reason in [:endpoint_required, :https_required, :invalid_endpoint] ->
        {:error, reason}

      _failure ->
        close(key)
        {:error, :connection_failed}
    end
  end

  defp start_integration(key, runtime, client_options, runtime_options) do
    child =
      {IntegrationSupervisor,
       key: key,
       runtime: runtime,
       client_options: client_options,
       runtime_options: runtime_options}

    case DynamicSupervisor.start_child(@connection_supervisor, child) do
      {:ok, owner} -> {:ok, owner}
      {:error, {:already_started, owner}} -> {:ok, owner}
      {:error, _reason} -> {:error, :connection_failed}
    end
  end

  defp ensure_ready(connection, runtime) do
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

  defp lookup_client(key) do
    case ConnectionNames.lookup(:client, key) do
      {:ok, client} -> client
      :error -> nil
    end
  end

  defp close_owner(owner) do
    case DynamicSupervisor.terminate_child(@connection_supervisor, owner) do
      :ok -> :closed
      {:error, :not_found} -> :absent
    end
  end

  defp active_connection_count do
    @connection_supervisor
    |> DynamicSupervisor.count_children()
    |> Map.fetch!(:active)
  end
end
