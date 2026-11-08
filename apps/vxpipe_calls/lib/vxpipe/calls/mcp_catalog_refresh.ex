defmodule Vxpipe.Calls.MCPCatalogRefresh do
  @moduledoc "Trusted tenant catalog maintenance, independent of browser authorization and queue libraries."

  alias Vxpipe.Calls.{MCPRuntimeCredentials, Repositories}
  alias Vxpipe.MCP.{ConnectionCheck, StaticConfiguration}

  @defaults [expiry_seconds: 3_600, reschedule_after_seconds: 1_800, batch_size: 100]
  @job_keys ~w(connection_id generation scheduled_at tenant)

  def sweep(options \\ []) do
    with {:ok, policy} <- policy(options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_catalog_refresh_repository),
         do: Repositories.call(repository, :enqueue_due, [policy])
  end

  def refresh(args, options \\ []) do
    with :ok <- job_identity(args),
         {:ok, policy} <- policy(options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_catalog_refresh_repository),
         {:ok, candidate} <- Repositories.call(repository, :fetch_due, [args, policy]) do
      case candidate do
        :obsolete -> :ok
        %{} -> refresh_candidate(args, candidate, options)
      end
    end
  end

  defp refresh_candidate(args, candidate, options) do
    tenant = args["tenant"]
    id = args["connection_id"]
    generation = args["generation"]

    with {:ok, saved} <- MCPRuntimeCredentials.resolve(tenant, id, generation, options),
         {:ok, configuration} <- configuration(saved),
         {:ok, discovered} <- discover(tenant, configuration, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository) do
      result =
        Repositories.call(repository, :refresh_catalog, [
          tenant,
          id,
          generation,
          Map.take(candidate, [:refreshed_at, :refresh_scheduled_at]),
          Map.take(discovered, [:server_name, :catalog])
        ])

      case result do
        {:ok, _record} -> :ok
        {:error, :stale_mcp_catalog} -> :ok
        {:error, :stale_mcp_connection} -> :ok
        {:error, :mcp_connection_not_found} -> :ok
        error -> error
      end
    end
  end

  defp configuration(saved) do
    {method, credentials} =
      if saved.connection.auth_method == "oauth" do
        {"bearer",
         %{
           "token" => saved.secrets["access_token"],
           "headers" => Map.get(saved.secrets, "headers", [])
         }}
      else
        {saved.connection.auth_method, saved.secrets}
      end

    StaticConfiguration.new(%{
      "endpoint" => saved.connection.endpoint,
      "auth_method" => method,
      "credentials" => credentials
    })
  end

  defp discover(tenant, configuration, options) do
    timeout = Application.get_env(:vxpipe_calls, :mcp_catalog_discovery_timeout_ms, 10_000)

    {protocol, context} =
      Keyword.get(
        options,
        :mcp_catalog_protocol,
        Application.get_env(:vxpipe_calls, :mcp_catalog_protocol, {ConnectionCheck, []})
      )

    protocol_options = context |> Keyword.merge(options) |> Keyword.put(:timeout, timeout)

    check =
      Keyword.get(options, :connection_check, &protocol.run(&1, &2, protocol_options))

    check.(tenant, configuration)
  end

  defp policy(options) do
    policy =
      Keyword.get(
        options,
        :catalog_refresh_policy,
        Application.get_env(:vxpipe_calls, :mcp_catalog_refresh, @defaults)
      )

    if Keyword.keyword?(policy) and
         Enum.sort(Keyword.keys(policy)) ==
           [:batch_size, :expiry_seconds, :reschedule_after_seconds] and
         positive?(Keyword.get(policy, :expiry_seconds), 31_536_000) and
         positive?(Keyword.get(policy, :reschedule_after_seconds), 86_400) and
         positive?(Keyword.get(policy, :batch_size), 1_000),
       do: {:ok, policy},
       else: {:error, :invalid_catalog_refresh_policy}
  end

  defp positive?(value, maximum), do: is_integer(value) and value > 0 and value <= maximum

  defp job_identity(args) when is_map(args) do
    with true <- Enum.sort(Map.keys(args)) == @job_keys,
         true <- is_binary(args["tenant"]) and byte_size(args["tenant"]) in 1..128,
         true <- is_binary(args["connection_id"]) and byte_size(args["connection_id"]) in 1..128,
         true <- is_integer(args["generation"]) and args["generation"] > 0,
         stamp when is_binary(stamp) <- args["scheduled_at"],
         {:ok, _time, 0} <- DateTime.from_iso8601(stamp) do
      :ok
    else
      _ -> {:error, :invalid_catalog_refresh_job}
    end
  end

  defp job_identity(_), do: {:error, :invalid_catalog_refresh_job}
end
