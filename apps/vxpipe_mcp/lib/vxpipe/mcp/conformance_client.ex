defmodule Vxpipe.MCP.ConformanceClient do
  @moduledoc false

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, Discovery, Invocation}

  @harness_version "0.1.16"

  @spec run(String.t(), String.t()) :: :ok | {:error, term()}
  def run(server_url, scenario) when is_binary(server_url) and is_binary(scenario) do
    with {:ok, key} <- connection_key(),
         {:ok, connection} <-
           Connections.open_loopback_test(key,
             endpoint: server_url,
             reconnect: true,
             limits: [
               max_request_bytes: 262_144,
               max_response_bytes: 262_144,
               max_stream_buffer_bytes: 262_144
             ]
           ) do
      try do
        run_scenario(scenario, connection)
      after
        Connections.close(connection)
      end
    end
  end

  defp run_scenario("initialize", connection) do
    case discover(connection) do
      {:ok, _catalog} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp run_scenario("tools_call", connection) do
    with {:ok, catalog} <- discover(connection),
         {:ok, _result} <-
           Invocation.call(
             Connection.client(connection),
             catalog,
             "add_numbers",
             %{"a" => 20, "b" => 22}
           ) do
      :ok
    end
  end

  defp run_scenario("sse-retry", connection) do
    with {:ok, catalog} <- discover(connection),
         {:ok, _result} <-
           Invocation.call(
             Connection.client(connection),
             catalog,
             "test_reconnection",
             %{},
             deadline_ms: 5_000
           ) do
      :ok
    end
  end

  defp run_scenario(_unsupported, _connection), do: {:error, :unsupported_scenario}

  defp discover(connection) do
    Discovery.discover(Connection.client(connection),
      deadline_ms: 5_000,
      max_pages: 20,
      max_decoded_bytes: 262_144
    )
  end

  defp connection_key do
    suffix = System.unique_integer([:positive, :monotonic])

    ConnectionKey.new(
      scope: :application,
      integration_id: "official-conformance-#{suffix}",
      credential_generation: @harness_version
    )
  end
end
