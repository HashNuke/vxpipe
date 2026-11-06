defmodule Vxpipe.MCP.DiscoveryIO do
  @moduledoc "Binds metadata DNS/HTTP work to the lifetime of its preflight owner."

  def options(options) do
    owner = self()
    resolver = Keyword.get(options, :dns_resolver, ExMCP.Internal.DNSResolver)
    client = Keyword.get(options, :http_client, ExMCP.Authorization.MetadataHTTPClient)

    options
    |> Keyword.put(:dns_resolver, fn host, timeout ->
      run(owner, fn -> invoke(resolver, :resolve, [host, timeout]) end)
    end)
    |> Keyword.put(:http_client, fn uri, address, opts ->
      run(owner, fn -> invoke(client, :get, [uri, address, opts]) end)
    end)
  end

  def run(owner, operation) do
    monitor = Process.monitor(owner)
    parent = self()
    result_ref = make_ref()
    worker = spawn_link(fn -> send(parent, {result_ref, safely(operation)}) end)

    receive do
      {^result_ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        Process.exit(worker, :kill)
        {:error, :cancelled}
    end
  end

  defp safely(operation) do
    operation.()
  rescue
    _error -> {:error, :discovery_io_failed}
  catch
    _kind, _reason -> {:error, :discovery_io_failed}
  end

  defp invoke(callback, _function, arguments) when is_function(callback),
    do: apply(callback, arguments)

  defp invoke(module, function, arguments), do: apply(module, function, arguments)
end
