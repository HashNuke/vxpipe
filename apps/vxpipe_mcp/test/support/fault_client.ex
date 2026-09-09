defmodule Vxpipe.MCP.FaultClient do
  @moduledoc false

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, Discovery, Invocation}

  @default_limit 262_144
  @default_deadline_ms 500

  def invoke(endpoint, fault, opts \\ []) when is_binary(endpoint) and is_atom(fault) do
    deadline_ms = Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    max_response_bytes = Keyword.get(opts, :max_response_bytes, @default_limit)
    max_stream_buffer_bytes = Keyword.get(opts, :max_stream_buffer_bytes, @default_limit)
    {:ok, key} = connection_key(fault)

    {:ok, connection} =
      Connections.open_loopback_test(key,
        endpoint: endpoint,
        limits: [
          max_response_bytes: max_response_bytes,
          max_stream_buffer_bytes: max_stream_buffer_bytes,
          request_timeout_ms: deadline_ms
        ]
      )

    try do
      with {:ok, catalog} <- Discovery.discover(Connection.client(connection)),
           result <-
             Invocation.call(
               Connection.client(connection),
               catalog,
               "fault_tool",
               %{},
               deadline_ms: deadline_ms
             ) do
        result
      end
    after
      Connections.close(connection)
    end
  end

  defp connection_key(fault) do
    suffix = System.unique_integer([:positive, :monotonic])

    ConnectionKey.new(
      integration_id: "wire-failure-#{fault}-#{suffix}",
      credential_generation: "fixture"
    )
  end
end
