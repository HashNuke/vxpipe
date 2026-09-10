defmodule Vxpipe.MCP.IdentityProbe do
  @moduledoc false

  alias Vxpipe.MCP.{Catalog, Connection, ConnectionKey, Connections, ReadyClientRuntime}

  @shutdown_timeout 1_000

  def measure(churn_count, offset \\ 0)

  def measure(churn_count, offset)
      when is_integer(churn_count) and churn_count > 0 and is_integer(offset) and offset >= 0 do
    {:ok, _applications} = Application.ensure_all_started(:vxpipe_mcp)

    warmup_range = (offset + 1)..(offset + churn_count)
    measured_range = (offset + churn_count + 1)..(offset + 2 * churn_count)

    Enum.each(warmup_range, &churn_once!/1)
    _ = :code.all_loaded()
    atoms_before = :erlang.system_info(:atom_count)
    modules_before = loaded_modules()

    Enum.each(measured_range, &churn_once!/1)
    :erlang.garbage_collect()

    %{
      atom_growth: :erlang.system_info(:atom_count) - atoms_before,
      module_growth: MapSet.size(MapSet.difference(loaded_modules(), modules_before)),
      atomized_values: atomized_external_values(measured_range)
    }
  end

  defp churn_once!(index) do
    name = "remote-tool-#{index}"

    {:ok, catalog} =
      Catalog.new([
        %{
          "name" => name,
          "inputSchema" => %{
            "type" => "object",
            "x-revision" => "schema-revision-#{index}"
          }
        }
      ])

    {:ok, %{"name" => ^name}} = Catalog.fetch(catalog, name)

    {:ok, key} =
      ConnectionKey.new(
        integration_id: "integration-#{index}",
        credential_generation: "generation-#{index}"
      )

    {:ok, connection} =
      Connections.open(
        key,
        [endpoint: "https://mcp-#{index}.example.test/rpc"],
        runtime: ReadyClientRuntime
      )

    owner_ref = Process.monitor(Connection.owner(connection))
    :ok = Connections.close(connection)

    receive do
      {:DOWN, ^owner_ref, :process, _pid, :shutdown} -> :ok
    after
      @shutdown_timeout -> raise "MCP connection did not stop"
    end

    :error = Connections.lookup(key)
  end

  defp atomized_external_values(range) do
    Enum.flat_map(range, fn index ->
      index
      |> external_values()
      |> Enum.filter(&(not atom_missing?(&1)))
    end)
  end

  defp external_values(index) do
    [
      "remote-tool-#{index}",
      "schema-revision-#{index}",
      "integration-#{index}",
      "generation-#{index}",
      "mcp-#{index}.example.test"
    ]
  end

  defp atom_missing?(value) do
    _existing = String.to_existing_atom(value)
    false
  rescue
    ArgumentError -> true
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> MapSet.new()
  end
end
