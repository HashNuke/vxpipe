defmodule Vxpipe.MCP.CheckWorker do
  @moduledoc false
  alias Vxpipe.MCP.{Catalog, CheckLifetime, ConnectionNames, Discovery}

  def start_link(key), do: Task.start_link(__MODULE__, :run, [key])

  def run(key) do
    with {:ok, request} <- CheckLifetime.claim(key, :worker),
         {:ok, client} <- ConnectionNames.lookup(:client, key) do
      result = inspect_client(client, request)
      disconnect(client)
      CheckLifetime.complete(key, result)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp inspect_client(client, request) do
    with {:ok, %{connection_status: :ready, protocol_version: "2025-11-25", server_info: info}} <-
           request.runtime.status(client),
         {:ok, name} <- server_name(info),
         remaining when remaining > 0 <-
           request.deadline - System.monotonic_time(:millisecond) - 250,
         {:ok, catalog} <-
           Discovery.discover(client,
             protocol: request.protocol,
             deadline_ms: min(remaining, 5_000)
           ) do
      {:ok, %{server_name: name, catalog: Catalog.tools(catalog)}}
    else
      _failed -> {:error, :mcp_connection_failed}
    end
  end

  defp disconnect(client) do
    GenServer.call(client, :disconnect, 250)
  catch
    :exit, _reason -> :ok
  end

  defp server_name(info) when is_map(info) do
    name = Map.get(info, "title", Map.get(info, "name"))

    if is_binary(name) and byte_size(name) in 1..200 and String.valid?(name) and
         String.trim(name) != "", do: {:ok, name}, else: {:error, :invalid_server_name}
  end

  defp server_name(_info), do: {:error, :invalid_server_name}
end
