defmodule Vxpipe.CallEngine.Tool.Executor do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{Call, Context, Definition}

  defstruct [:maximum_result_bytes, tools: %{}]

  @type t :: %__MODULE__{maximum_result_bytes: pos_integer(), tools: map()}

  @spec new([module()], pos_integer()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(modules, maximum_result_bytes)
      when is_list(modules) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    with {:ok, tools} <- build_tools(modules),
         true <- map_size(tools) == length(modules) do
      {:ok, %__MODULE__{tools: tools, maximum_result_bytes: maximum_result_bytes}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_modules, _maximum_result_bytes), do: {:error, :invalid_configuration}

  @spec definitions(t()) :: [Definition.t()]
  def definitions(%__MODULE__{} = executor) do
    executor.tools
    |> Map.values()
    |> Enum.map(& &1.definition)
    |> Enum.sort_by(& &1.name)
  end

  @spec execute(t(), Call.t(), Context.t()) ::
          {:ok, term()}
          | {:error, :invalid_arguments | :invalid_result | :tool_failed | :unknown_tool}
  def execute(%__MODULE__{} = executor, %Call{} = call, %Context{} = context) do
    case Map.fetch(executor.tools, call.name) do
      {:ok, tool} ->
        execute_tool(tool.module, call.arguments, context, executor.maximum_result_bytes)

      :error ->
        {:error, :unknown_tool}
    end
  end

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
      is_map(definition.parameters)
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
