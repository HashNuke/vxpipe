defmodule Vxpipe.MCP.Telemetry do
  @moduledoc """
  Emits bounded operational events owned by the standalone MCP client.

  Durations use the Erlang `:native` time unit from a monotonic clock. Metadata
  contains only closed operation and outcome categories plus an optional local
  client PID. External identities, credentials, tool data, and protocol payloads
  are deliberately excluded.
  """

  @connection_stop_event [:vxpipe, :mcp, :connection, :stop]
  @request_stop_event [:vxpipe, :mcp, :request, :stop]
  @events [@connection_stop_event, @request_stop_event]

  @connection_operations [:open, :close]
  @connection_outcomes [:opened, :reused, :failed, :closed, :absent]
  @request_operations [:discovery, :invocation]
  @request_outcomes [
    :ok,
    :failed,
    :timeout,
    :rejected,
    :too_large,
    :not_submitted,
    :remote_error,
    :unknown
  ]

  @doc "Returns the complete framework-independent MCP event contract."
  @spec events() :: [nonempty_list(atom())]
  def events, do: @events

  @doc "Returns a timestamp from the clock used for elapsed measurements."
  @spec started_at() :: integer()
  def started_at, do: System.monotonic_time()

  @doc "Emits a terminal connection lifecycle observation."
  @spec connection_stop(
          integer(),
          :open | :close,
          :opened | :reused | :failed | :closed | :absent,
          non_neg_integer(),
          pid() | nil
        ) :: :ok
  def connection_stop(started_at, operation, outcome, active_connections, client)
      when is_integer(started_at) and operation in @connection_operations and
             outcome in @connection_outcomes and is_integer(active_connections) and
             active_connections >= 0 and (is_pid(client) or is_nil(client)) do
    :telemetry.execute(
      @connection_stop_event,
      %{
        active_connections: active_connections,
        count: 1,
        duration: System.monotonic_time() - started_at
      },
      metadata(operation, outcome, client)
    )
  end

  @doc "Emits a terminal discovery or invocation observation."
  @spec request_stop(
          integer(),
          :discovery | :invocation,
          :ok
          | :failed
          | :timeout
          | :rejected
          | :too_large
          | :not_submitted
          | :remote_error
          | :unknown,
          pid() | nil
        ) :: :ok
  def request_stop(started_at, operation, outcome, client)
      when is_integer(started_at) and operation in @request_operations and
             outcome in @request_outcomes and (is_pid(client) or is_nil(client)) do
    :telemetry.execute(
      @request_stop_event,
      %{count: 1, duration: System.monotonic_time() - started_at},
      metadata(operation, outcome, client)
    )
  end

  defp metadata(operation, outcome, nil), do: %{operation: operation, outcome: outcome}

  defp metadata(operation, outcome, client) do
    %{operation: operation, outcome: outcome, client: client}
  end
end
