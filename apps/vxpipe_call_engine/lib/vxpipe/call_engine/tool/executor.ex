defmodule Vxpipe.CallEngine.Tool.Executor do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.Tool.{Call, Context, Definition}

  defstruct [:maximum_result_bytes, :remote_mcp, remote_tools: MapSet.new(), tools: %{}]

  @type t :: %__MODULE__{
          maximum_result_bytes: pos_integer(),
          remote_mcp: GenServer.server() | nil,
          remote_tools: MapSet.t(String.t()),
          tools: map()
        }

  @spec new([module()], pos_integer()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(modules, maximum_result_bytes), do: new(modules, maximum_result_bytes, [])

  @spec new([module()], pos_integer(), keyword()) ::
          {:ok, t()} | {:error, :invalid_configuration}
  def new(modules, maximum_result_bytes, options)
      when is_list(modules) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 and
             is_list(options) do
    with {:ok, options} <- Keyword.validate(options, remote_mcp: nil, remote_tools: []),
         {:ok, tools} <- build_tools(modules),
         true <- map_size(tools) == length(modules),
         {:ok, remote_tools} <-
           build_remote_tools(options[:remote_tools], options[:remote_mcp], tools) do
      {:ok,
       %__MODULE__{
         tools: tools,
         maximum_result_bytes: maximum_result_bytes,
         remote_mcp: options[:remote_mcp],
         remote_tools: remote_tools
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_modules, _maximum_result_bytes, _options), do: {:error, :invalid_configuration}

  @spec definitions(t()) :: [Definition.t()]
  def definitions(%__MODULE__{} = executor) do
    executor.tools
    |> Map.values()
    |> Enum.map(& &1.definition)
    |> Enum.sort_by(& &1.name)
  end

  @spec background?(t(), String.t()) :: boolean()
  def background?(%__MODULE__{} = executor, name) when is_binary(name) do
    MapSet.member?(executor.remote_tools, name) or background_host_tool?(executor.tools, name)
  end

  @spec execute(t(), Call.t(), Context.t()) ::
          {:ok, term()}
          | {:error,
             :invalid_arguments | :invalid_result | :tool_failed | :unknown | :unknown_tool}
  def execute(%__MODULE__{} = executor, %Call{} = call, %Context{} = context) do
    case Map.fetch(executor.tools, call.name) do
      {:ok, tool} ->
        execute_tool(tool.module, call.arguments, context, executor.maximum_result_bytes)

      :error ->
        execute_remote_tool(executor, call.name, call.arguments)
    end
  end

  defp build_remote_tools(configured_names, remote_mcp, tools) when is_list(configured_names) do
    names = MapSet.new(configured_names)

    cond do
      MapSet.size(names) != length(configured_names) ->
        {:error, :invalid_configuration}

      Enum.any?(names, &(not is_binary(&1) or String.trim(&1) == "")) ->
        {:error, :invalid_configuration}

      MapSet.size(names) == 0 and remote_mcp != nil ->
        {:error, :invalid_configuration}

      MapSet.size(names) > 0 and remote_mcp == nil ->
        {:error, :invalid_configuration}

      Enum.any?(names, &Map.has_key?(tools, &1)) ->
        {:error, :invalid_configuration}

      true ->
        {:ok, names}
    end
  end

  defp build_remote_tools(_names, _remote_mcp, _tools), do: {:error, :invalid_configuration}

  defp build_tools(modules) do
    Enum.reduce_while(modules, {:ok, %{}}, fn module, {:ok, tools} ->
      with true <- is_atom(module) and Code.ensure_loaded?(module),
           true <- function_exported?(module, :definition, 0),
           true <- function_exported?(module, :execute, 2),
           %Definition{} = definition <- module.definition(),
           true <- valid_definition?(definition),
           false <- Map.has_key?(tools, definition.name) do
        {:cont, {:ok, Map.put(tools, definition.name, %{definition: definition, module: module})}}
      else
        _invalid -> {:halt, {:error, :invalid_configuration}}
      end
    end)
  end

  defp valid_definition?(definition) do
    is_binary(definition.name) and String.trim(definition.name) != "" and
      is_binary(definition.description) and String.trim(definition.description) != "" and
      is_map(definition.parameters) and definition.execution in [:inline, :background]
  end

  defp background_host_tool?(tools, name) do
    match?(%{definition: %Definition{execution: :background}}, Map.get(tools, name))
  end

  defp execute_remote_tool(executor, name, arguments) do
    if MapSet.member?(executor.remote_tools, name) do
      IntegrationOwner.execute(executor.remote_mcp, name, arguments)
    else
      {:error, :unknown_tool}
    end
  end

  defp execute_tool(module, arguments, context, maximum_result_bytes) when is_map(arguments) do
    result =
      try do
        module.execute(arguments, context)
      rescue
        _exception -> {:error, :tool_failed}
      catch
        _kind, _reason -> {:error, :tool_failed}
      end

    normalize_result(result, maximum_result_bytes)
  end

  defp execute_tool(_module, _arguments, _context, _maximum_result_bytes),
    do: {:error, :invalid_arguments}

  defp normalize_result({:ok, result}, maximum_result_bytes) do
    try do
      if byte_size(JSON.encode!(result)) <= maximum_result_bytes do
        {:ok, result}
      else
        {:error, :invalid_result}
      end
    rescue
      _exception -> {:error, :invalid_result}
    end
  end

  defp normalize_result({:error, :invalid_arguments}, _maximum_result_bytes),
    do: {:error, :invalid_arguments}

  defp normalize_result({:error, _reason}, _maximum_result_bytes), do: {:error, :tool_failed}
  defp normalize_result(_result, _maximum_result_bytes), do: {:error, :invalid_result}
end
