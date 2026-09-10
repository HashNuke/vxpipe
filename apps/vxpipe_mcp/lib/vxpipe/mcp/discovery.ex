defmodule Vxpipe.MCP.Discovery do
  @moduledoc """
  Fetches one complete, bounded snapshot of an MCP server's tool catalog.

  A partial result is never returned as a usable catalog.
  """

  alias Vxpipe.MCP.{Catalog, ExMCPClient, Telemetry}

  @default_deadline_ms 5_000
  @default_max_pages 20
  @default_max_decoded_bytes 1_000_000

  @type error ::
          :discovery_page_limit_exceeded
          | :discovery_failed
          | :discovery_timed_out
          | :discovery_too_large
          | :invalid_discovery_response
          | :repeated_cursor
          | Catalog.error()
          | {:invalid_option, :deadline_ms | :max_decoded_bytes | :max_pages}

  @spec discover(term(), keyword()) :: {:ok, Catalog.t()} | {:error, error()}
  def discover(client, opts \\ []) do
    started_at = Telemetry.started_at()
    protocol = Keyword.get(opts, :protocol, ExMCPClient)
    deadline_ms = Keyword.get(opts, :deadline_ms, @default_deadline_ms)
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)
    max_decoded_bytes = Keyword.get(opts, :max_decoded_bytes, @default_max_decoded_bytes)

    result =
      with :ok <- positive(:deadline_ms, deadline_ms),
           :ok <- positive(:max_pages, max_pages),
           :ok <- positive(:max_decoded_bytes, max_decoded_bytes) do
        state = %{
          client: client,
          protocol: protocol,
          cursor: nil,
          seen_cursors: MapSet.new(),
          deadline: now() + deadline_ms,
          page_count: 0,
          max_pages: max_pages,
          decoded_bytes: 0,
          max_decoded_bytes: max_decoded_bytes,
          tools: []
        }

        fetch_page(state)
      end

    Telemetry.request_stop(started_at, :discovery, telemetry_outcome(result), client_pid(client))
    result
  end

  defp fetch_page(%{page_count: page_count, max_pages: max_pages})
       when page_count >= max_pages,
       do: {:error, :discovery_page_limit_exceeded}

  defp fetch_page(state) do
    with {:ok, timeout} <- remaining(state.deadline),
         {:ok, page} <- request_page(state, timeout),
         {:ok, page_bytes} <- encoded_size(page),
         :ok <- within_byte_budget(state, page_bytes),
         {:ok, tools, next_cursor} <- parse_page(page),
         {:ok, seen_cursors} <- accept_cursor(next_cursor, state.seen_cursors) do
      state = %{
        state
        | cursor: next_cursor,
          seen_cursors: seen_cursors,
          page_count: state.page_count + 1,
          decoded_bytes: state.decoded_bytes + page_bytes,
          tools: Enum.reverse(tools, state.tools)
      }

      if next_cursor do
        fetch_page(state)
      else
        state.tools
        |> Enum.reverse()
        |> Catalog.new()
      end
    end
  end

  defp request_page(state, timeout) do
    case state.protocol.list_tools(state.client, state.cursor, timeout) do
      {:ok, page} -> {:ok, page}
      {:error, _reason} -> {:error, :discovery_failed}
      _other -> {:error, :invalid_discovery_response}
    end
  end

  defp encoded_size(page) when is_map(page) do
    case Jason.encode(page) do
      {:ok, encoded} -> {:ok, byte_size(encoded)}
      {:error, _reason} -> {:error, :invalid_discovery_response}
    end
  end

  defp encoded_size(_page), do: {:error, :invalid_discovery_response}

  defp within_byte_budget(state, page_bytes) do
    if state.decoded_bytes + page_bytes <= state.max_decoded_bytes do
      :ok
    else
      {:error, :discovery_too_large}
    end
  end

  defp parse_page(%{"tools" => tools} = page) when is_list(tools) do
    case Map.get(page, "nextCursor") do
      nil -> {:ok, tools, nil}
      cursor when is_binary(cursor) and cursor != "" -> {:ok, tools, cursor}
      _invalid -> {:error, :invalid_discovery_response}
    end
  end

  defp parse_page(_page), do: {:error, :invalid_discovery_response}

  defp accept_cursor(nil, seen_cursors), do: {:ok, seen_cursors}

  defp accept_cursor(cursor, seen_cursors) do
    if MapSet.member?(seen_cursors, cursor) do
      {:error, :repeated_cursor}
    else
      {:ok, MapSet.put(seen_cursors, cursor)}
    end
  end

  defp remaining(deadline) do
    case deadline - now() do
      remaining when remaining > 0 -> {:ok, remaining}
      _expired -> {:error, :discovery_timed_out}
    end
  end

  defp positive(_name, value) when is_integer(value) and value > 0, do: :ok
  defp positive(name, _value), do: {:error, {:invalid_option, name}}

  defp telemetry_outcome({:ok, %Catalog{}}), do: :ok
  defp telemetry_outcome({:error, :discovery_timed_out}), do: :timeout
  defp telemetry_outcome({:error, :discovery_too_large}), do: :too_large

  defp telemetry_outcome({:error, reason})
       when reason in [
              :discovery_page_limit_exceeded,
              :duplicate_tool_name,
              :invalid_discovery_response,
              :malformed_tool,
              :repeated_cursor
            ],
       do: :rejected

  defp telemetry_outcome({:error, {:invalid_option, _name}}), do: :rejected
  defp telemetry_outcome({:error, :discovery_failed}), do: :failed
  defp telemetry_outcome({:error, _reason}), do: :failed

  defp client_pid(client) when is_pid(client), do: client
  defp client_pid(_client), do: nil

  defp now, do: System.monotonic_time(:millisecond)
end
