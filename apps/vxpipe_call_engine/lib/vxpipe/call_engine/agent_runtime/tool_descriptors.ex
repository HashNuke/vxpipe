defmodule Vxpipe.CallEngine.AgentRuntime.ToolDescriptors do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.CallEngine.CallVariables.Binding, as: VariablesBinding
  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{Definition, InvocationBinding}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding, as: TransferBinding
  alias Vxpipe.CallEngine.Tool.PlatformCatalog

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
    descriptors(bindings, variable_binding, &descriptor(&1, remote_owner))
  end

  def compile(_bindings, _variable_binding, _remote_owner), do: {:error, :invalid_tool_binding}

  @doc "Validates provider-safe schemas without constructing an executable MCP binding."
  def project(bindings, variable_binding \\ nil)

  def project(bindings, variable_binding)
      when is_map(bindings) and
             (is_nil(variable_binding) or is_struct(variable_binding, VariablesBinding)) do
    with {:ok, descriptors} <- descriptors(bindings, variable_binding, &projection_descriptor/1) do
      if length(Enum.uniq_by(descriptors, & &1.name)) == length(descriptors),
        do: {:ok, Enum.map(descriptors, &Map.take(&1, [:name, :description, :input_schema]))},
        else: {:error, :invalid_tool_binding}
    end
  end

  def project(_bindings, _variable_binding), do: {:error, :invalid_tool_binding}

  defp descriptors(bindings, variable_binding, build_descriptor) do
    with {:ok, tool_descriptors} <- compile_bindings(bindings, build_descriptor),
         {:ok, variable_descriptors} <- compile_variable_bindings(variable_binding) do
      {:ok, Enum.sort_by(tool_descriptors ++ variable_descriptors, & &1.name)}
    end
  end

  defp compile_bindings(bindings, build_descriptor) do
    bindings
    |> Enum.sort_by(fn {name, _binding} -> name end)
    |> Enum.reduce_while({:ok, []}, fn entry, result ->
      compile_binding(entry, build_descriptor, result)
    end)
    |> case do
      {:ok, descriptors} -> {:ok, Enum.reverse(descriptors)}
      {:error, :invalid_tool_binding} = error -> error
    end
  end

  defp compile_binding(
         {name, %ToolBinding{name: name} = resolved},
         build_descriptor,
         {:ok, descriptors}
       )
       when is_binary(name) do
    case build_descriptor.(resolved) do
      {:ok, descriptor} -> {:cont, {:ok, [descriptor | descriptors]}}
      {:error, _reason} -> {:halt, {:error, :invalid_tool_binding}}
    end
  end

  defp compile_binding(_entry, _build_descriptor, {:ok, _descriptors}),
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
         %ToolBinding{name: name, type: :platform, action: action} = resolved,
         _remote_owner
       ) do
    with true <- PlatformCatalog.action?(action),
         {:ok, binding} <- InvocationBinding.from_resolved(resolved),
         %Definition{description: description, parameters: parameters} <- action.definition(),
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

  defp descriptor(
         %ToolBinding{type: :mcp, remote: %ResolvedTool{}} = resolved,
         remote_owner
       ) do
    with {:ok, binding} <- InvocationBinding.from_remote(resolved, remote_owner),
         {:ok, descriptor} <- remote_descriptor(resolved, binding) do
      {:ok, descriptor}
    else
      _invalid -> {:error, :invalid_tool_binding}
    end
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end

  defp descriptor(
         %ToolBinding{
           name: "transfer",
           type: :participant_transfer,
           transfer: %TransferBinding{} = transfer
         } = resolved,
         _remote_owner
       ) do
    with {:ok, binding} <- InvocationBinding.from_participant_transfer(resolved),
         %Definition{description: description, parameters: parameters} <-
           ParticipantTransfer.definition(transfer),
         {:ok, descriptor} <-
           ToolDescriptor.new(
             name: "transfer",
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

  defp descriptor(%ToolBinding{}, _remote_owner), do: {:error, :invalid_tool_binding}

  defp projection_descriptor(%ToolBinding{
         name: name,
         type: :mcp,
         remote: %ResolvedTool{} = remote
       }) do
    ToolDescriptor.project(
      name: name,
      description: remote_description(remote.description, name),
      input_schema: remote.input_schema
    )
  end

  defp projection_descriptor(resolved), do: descriptor(resolved, nil)

  defp remote_descriptor(%ToolBinding{name: name, remote: remote}, binding) do
    ToolDescriptor.new(
      name: name,
      description: remote_description(remote.description, name),
      input_schema: remote.input_schema,
      binding: binding
    )
  rescue
    _exception -> {:error, :invalid_tool_binding}
  end

  defp remote_description("", name), do: "Call #{name}."
  defp remote_description(description, _name), do: description

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
