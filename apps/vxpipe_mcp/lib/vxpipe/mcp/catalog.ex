defmodule Vxpipe.MCP.Catalog do
  @moduledoc """
  A complete, immutable snapshot of a remote MCP tool catalog.

  Remote names, descriptions, schemas, annotations, and extensions remain string-keyed
  data. Building a catalog fails if any definition is malformed or ambiguous.
  """

  @enforce_keys [:tools, :tools_by_name]
  defstruct [:tools, :tools_by_name]

  @opaque t :: %__MODULE__{
            tools: [map()],
            tools_by_name: %{String.t() => map()}
          }
  @type error :: :duplicate_tool_name | :malformed_tool

  @spec new([map()]) :: {:ok, t()} | {:error, error()}
  def new(tools) when is_list(tools) do
    with {:ok, tools_by_name} <- index(tools) do
      {:ok, %__MODULE__{tools: tools, tools_by_name: tools_by_name}}
    end
  end

  @spec tools(t()) :: [map()]
  def tools(%__MODULE__{tools: tools}), do: tools

  @spec fetch(t(), String.t()) :: {:ok, map()} | {:error, :unknown_tool}
  def fetch(%__MODULE__{tools_by_name: tools_by_name}, name) when is_binary(name) do
    case Map.fetch(tools_by_name, name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, :unknown_tool}
    end
  end

  defp index(tools) do
    Enum.reduce_while(tools, {:ok, %{}}, fn tool, {:ok, by_name} ->
      with {:ok, name} <- tool_name(tool),
           false <- Map.has_key?(by_name, name) do
        {:cont, {:ok, Map.put(by_name, name, tool)}}
      else
        true -> {:halt, {:error, :duplicate_tool_name}}
        _invalid -> {:halt, {:error, :malformed_tool}}
      end
    end)
  end

  defp tool_name(%{"name" => name, "inputSchema" => schema})
       when is_binary(name) and name != "" and is_map(schema),
       do: {:ok, name}

  defp tool_name(_tool), do: {:error, :malformed_tool}
end
