defmodule Vxpipe.MCP.Invocation do
  @moduledoc """
  Validates and invokes one tool from an already complete MCP catalog snapshot.

  Validation failures are returned before the protocol boundary is called. Once the
  boundary is called, transport ambiguity remains an explicit unknown outcome.
  """

  alias Vxpipe.MCP.{ArgumentValidator, Catalog, ExMCPClient}

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
    protocol = Keyword.get(opts, :protocol, ExMCPClient)
    deadline_ms = Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    max_result_bytes = Keyword.get(opts, :max_result_bytes, @default_max_result_bytes)

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

  defp now, do: System.monotonic_time(:millisecond)
end
