defmodule Vxpipe.Calls.EditorToolCatalog do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationCatalog}
  alias Vxpipe.CallEngine.Tool.{Definition, PlatformCatalog}

  def list(tenant, options) do
    {remote, available?} = remote_tools(tenant, options)
    built_in = Enum.map(PlatformCatalog.definitions(), &entry("platform", &1))

    %{
      tools: Enum.filter(host_tools(options) ++ built_in ++ remote, &selectable?/1),
      mcp_available: available?
    }
  end

  defp remote_tools(tenant, options) do
    store = Keyword.get(options, :mcp_catalog_store, CatalogStore)

    case CatalogStore.snapshot(store) do
      {:ok, catalog} ->
        {Enum.map(IntegrationCatalog.tools(catalog, tenant), &Map.put(&1, :type, "mcp")), true}
    end
  catch
    :exit, _reason -> {[], false}
  end

  defp host_tools(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    registries = Keyword.get(options, :registries, Keyword.get(configured, :registries, %{}))

    registries
    |> Map.get(:host_tools, %{})
    |> Enum.flat_map(fn {name, action} -> host_entry(name, action) end)
    |> Enum.sort_by(& &1.tool)
  end

  defp host_entry(name, action) when is_atom(action) do
    if Code.ensure_loaded?(action) and function_exported?(action, :definition, 0) and
         function_exported?(action, :execute, 2) do
      case action.definition() do
        %Definition{name: ^name, description: description} = definition
        when is_binary(description) ->
          [entry("host", definition)]

        _invalid ->
          []
      end
    else
      []
    end
  end

  defp host_entry(_name, _action), do: []

  defp entry(type, definition),
    do: %{type: type, tool: definition.name, description: definition.description}

  defp selectable?(tool) do
    identifier?(tool.tool) and
      (tool.type != "mcp" or identifier?(tool.integration)) and
      (tool.type != "host" or
         tool.tool not in ~w(transfer read_variables update_variables update_variable))
  end

  defp identifier?(name), do: is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, name)
end
