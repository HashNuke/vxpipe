defmodule Vxpipe.MCP.Invocation do
  @moduledoc """
  Validates and invokes one tool from an already complete MCP catalog snapshot.

  Validation failures are returned before the protocol boundary is called. Once the
  boundary is called, transport ambiguity remains an explicit unknown outcome.
  """

  alias Vxpipe.MCP.{ArgumentValidator, Catalog, ExMCPClient, Telemetry}

  @default_deadline_ms 30_000
  @default_max_result_bytes 262_144

  @type error ::
          :invalid_arguments
          | :invalid_tool_result
          | :invocation_timed_out
          | :not_submitted
          | :outcome_unknown
          | :remote_error
          | :result_too_large
          | :unknown_tool
          | :unsupported_input_schema
          | {:invalid_option, :deadline_ms | :max_result_bytes}

  @spec call(term(), Catalog.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, error()}
  def call(client, %Catalog{} = catalog, name, arguments, opts \\ []) do
    started_at = Telemetry.started_at()
    protocol = Keyword.get(opts, :protocol, ExMCPClient)
    deadline_ms = Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    max_result_bytes = Keyword.get(opts, :max_result_bytes, @default_max_result_bytes)

    result =
      with :ok <- positive(:deadline_ms, deadline_ms),
           :ok <- positive(:max_result_bytes, max_result_bytes),
           deadline = now() + deadline_ms,
           {:ok, tool} <- Catalog.fetch(catalog, name),
           :ok <- ArgumentValidator.validate(tool["inputSchema"], arguments),
           {:ok, timeout} <- remaining(deadline),
           {:ok, result} <- protocol.call_tool(client, name, arguments, timeout),
           :ok <- within_result_budget(result, max_result_bytes) do
        {:ok, result}
      end

    Telemetry.request_stop(started_at, :invocation, telemetry_outcome(result), client_pid(client))
    result
  end

  defp within_result_budget(result, max_result_bytes) when is_map(result) do
    case Jason.encode(result) do
      {:ok, encoded} when byte_size(encoded) <= max_result_bytes -> :ok
      {:ok, _encoded} -> {:error, :result_too_large}
      {:error, _reason} -> {:error, :invalid_tool_result}
    end
  end

  defp within_result_budget(_result, _max_result_bytes), do: {:error, :invalid_tool_result}

  defp remaining(deadline) do
    case deadline - now() do
      remaining when remaining > 0 -> {:ok, remaining}
      _expired -> {:error, :invocation_timed_out}
    end
  end

  defp positive(_name, value) when is_integer(value) and value > 0, do: :ok
  defp positive(name, _value), do: {:error, {:invalid_option, name}}

  defp telemetry_outcome({:ok, result}) when is_map(result), do: :ok
  defp telemetry_outcome({:error, :invocation_timed_out}), do: :timeout
  defp telemetry_outcome({:error, :result_too_large}), do: :too_large
  defp telemetry_outcome({:error, :not_submitted}), do: :not_submitted
  defp telemetry_outcome({:error, :remote_error}), do: :remote_error
  defp telemetry_outcome({:error, :outcome_unknown}), do: :unknown

  defp telemetry_outcome({:error, reason})
       when reason in [
              :invalid_arguments,
              :unknown_tool,
              :unsupported_input_schema
            ],
       do: :rejected

  defp telemetry_outcome({:error, {:invalid_option, _name}}), do: :rejected
  defp telemetry_outcome({:error, _reason}), do: :failed

  defp client_pid(client) when is_pid(client), do: client
  defp client_pid(_client), do: nil

  defp now, do: System.monotonic_time(:millisecond)
end
