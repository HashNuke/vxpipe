defmodule Vxpipe.CallEngine.AgentRuntime.ToolDescriptors do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{Definition, InvocationBinding}

  @spec compile(%{optional(String.t()) => ToolBinding.t()}) ::
          {:ok, [ToolDescriptor.t()]} | {:error, :invalid_tool_binding}
  def compile(bindings) when is_map(bindings) do
    bindings
    |> Enum.sort_by(fn {name, _binding} -> name end)
    |> Enum.reduce_while({:ok, []}, &compile_binding/2)
    |> case do
      {:ok, descriptors} -> {:ok, Enum.reverse(descriptors)}
      {:error, :invalid_tool_binding} = error -> error
    end
  end

  def compile(_bindings), do: {:error, :invalid_tool_binding}

  defp compile_binding({name, %ToolBinding{name: name} = resolved}, {:ok, descriptors})
       when is_binary(name) do
    case descriptor(resolved) do
      {:ok, descriptor} -> {:cont, {:ok, [descriptor | descriptors]}}
      {:error, :invalid_tool_binding} = error -> {:halt, error}
    end
  end

  defp compile_binding(_entry, {:ok, _descriptors}),
    do: {:halt, {:error, :invalid_tool_binding}}

  defp descriptor(%ToolBinding{name: name, action: action} = resolved) do
    with {:ok, binding} <- InvocationBinding.from_resolved(resolved),
         %Definition{name: ^name, description: description, parameters: parameters} <-
           action.definition(),
         {:ok, descriptor} <-
           ToolDescriptor.new(
             name: name,
             description: description,
             input_schema: parameters,
             binding: binding
           ) do
      {:ok, descriptor}
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end
end
