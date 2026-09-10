defmodule Vxpipe.CallEngine.AgentRuntime.ToolDescriptors do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.CallEngine.CallVariables.Binding, as: VariablesBinding
  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{Definition, InvocationBinding}

  @spec compile(%{optional(String.t()) => ToolBinding.t()}) ::
          {:ok, [ToolDescriptor.t()]} | {:error, :invalid_tool_binding}
  def compile(bindings), do: compile(bindings, nil, nil)

  @spec compile(%{optional(String.t()) => ToolBinding.t()}, nil | VariablesBinding.t()) ::
          {:ok, [ToolDescriptor.t()]} | {:error, :invalid_tool_binding}
  def compile(bindings, variable_binding), do: compile(bindings, variable_binding, nil)

  @spec compile(
          %{optional(String.t()) => ToolBinding.t()},
          nil | VariablesBinding.t(),
          nil | GenServer.server()
        ) :: {:ok, [ToolDescriptor.t()]} | {:error, :invalid_tool_binding}
  def compile(bindings, variable_binding, remote_owner)
      when is_map(bindings) and
             (is_nil(variable_binding) or is_struct(variable_binding, VariablesBinding)) do
    with {:ok, tool_descriptors} <- compile_bindings(bindings, remote_owner),
         {:ok, variable_descriptors} <- compile_variable_bindings(variable_binding) do
      {:ok, Enum.sort_by(tool_descriptors ++ variable_descriptors, & &1.name)}
    end
  end

  def compile(_bindings, _variable_binding, _remote_owner), do: {:error, :invalid_tool_binding}

  defp compile_bindings(bindings, remote_owner) do
    bindings
    |> Enum.sort_by(fn {name, _binding} -> name end)
    |> Enum.reduce_while({:ok, []}, fn entry, result ->
      compile_binding(entry, remote_owner, result)
    end)
    |> case do
      {:ok, descriptors} -> {:ok, Enum.reverse(descriptors)}
      {:error, :invalid_tool_binding} = error -> error
    end
  end

  defp compile_binding(
         {name, %ToolBinding{name: name} = resolved},
         remote_owner,
         {:ok, descriptors}
       )
       when is_binary(name) do
    case descriptor(resolved, remote_owner) do
      {:ok, descriptor} -> {:cont, {:ok, [descriptor | descriptors]}}
      {:error, :invalid_tool_binding} = error -> {:halt, error}
    end
  end

  defp compile_binding(_entry, _remote_owner, {:ok, _descriptors}),
    do: {:halt, {:error, :invalid_tool_binding}}

  defp descriptor(%ToolBinding{name: name, type: :host, action: action} = resolved, _remote_owner) do
    with {:ok, binding} <- InvocationBinding.from_resolved(resolved),
         {:ok, descriptor} <- descriptor(action, name, binding) do
      {:ok, descriptor}
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end

  defp descriptor(
         %ToolBinding{name: name, type: :mcp, remote: %ResolvedTool{} = remote} = resolved,
         remote_owner
       ) do
    with {:ok, binding} <- InvocationBinding.from_remote(resolved, remote_owner),
         {:ok, descriptor} <-
           ToolDescriptor.new(
             name: name,
             description: remote.description,
             input_schema: remote.input_schema,
             binding: binding
           ) do
      {:ok, descriptor}
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end

  defp descriptor(%ToolBinding{}, _remote_owner), do: {:error, :invalid_tool_binding}

  defp compile_variable_bindings(nil), do: {:ok, []}

  defp compile_variable_bindings(%VariablesBinding{} = variable_binding) do
    variable_binding
    |> VariablesBinding.actions()
    |> Enum.reduce_while({:ok, []}, fn action, {:ok, descriptors} ->
      case variable_descriptor(action, variable_binding) do
        {:ok, descriptor} -> {:cont, {:ok, [descriptor | descriptors]}}
        {:error, :invalid_tool_binding} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, descriptors} -> {:ok, Enum.reverse(descriptors)}
      {:error, :invalid_tool_binding} = error -> error
    end
  end

  defp variable_descriptor(action, variable_binding) do
    with %Definition{name: name} <- action.definition(),
         {:ok, binding} <- InvocationBinding.from_call_variables(name, variable_binding),
         {:ok, descriptor} <- descriptor(action, name, binding) do
      {:ok, descriptor}
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end

  defp descriptor(action, name, binding) do
    with %Definition{name: ^name, description: description, parameters: parameters} <-
           action.definition() do
      ToolDescriptor.new(
        name: name,
        description: description,
        input_schema: parameters,
        binding: binding
      )
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  end
end
