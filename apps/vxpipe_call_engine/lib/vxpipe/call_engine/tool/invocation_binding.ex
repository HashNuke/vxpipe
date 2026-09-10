defmodule Vxpipe.CallEngine.Tool.InvocationBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding, as: VariablesBinding
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  @derive {Inspect, only: [:name, :conversation_mode]}
  @enforce_keys [:name, :conversation_mode, :handler]
  defstruct @enforce_keys

  @type handler :: {:host, module()} | {:call_variables, VariablesBinding.t()}
  @type t :: %__MODULE__{
          name: String.t(),
          conversation_mode: :blocking | :non_blocking,
          handler: handler()
        }

  @spec from_resolved(ToolBinding.t()) :: {:ok, t()} | {:error, :invalid_binding}
  def from_resolved(%ToolBinding{
        name: name,
        type: :host,
        conversation_mode: conversation_mode,
        action: action
      })
      when is_binary(name) and conversation_mode in [:blocking, :non_blocking] and
             is_atom(action) do
    if Code.ensure_loaded?(action) and function_exported?(action, :definition, 0) and
         function_exported?(action, :execute, 2) do
      {:ok,
       %__MODULE__{
         name: name,
         conversation_mode: conversation_mode,
         handler: {:host, action}
       }}
    else
      {:error, :invalid_binding}
    end
  end

  def from_resolved(%ToolBinding{}), do: {:error, :invalid_binding}

  @spec from_call_variables(String.t(), VariablesBinding.t()) ::
          {:ok, t()} | {:error, :invalid_binding}
  def from_call_variables(name, %VariablesBinding{} = binding) when is_binary(name) do
    if VariablesBinding.permitted_tool?(binding, name) and is_pid(binding.server) do
      {:ok,
       %__MODULE__{
         name: name,
         conversation_mode: :blocking,
         handler: {:call_variables, binding}
       }}
    else
      {:error, :invalid_binding}
    end
  end

  def from_call_variables(_name, _binding), do: {:error, :invalid_binding}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{
        name: name,
        conversation_mode: conversation_mode,
        handler: {:host, action}
      }) do
    is_binary(name) and name != "" and conversation_mode in [:blocking, :non_blocking] and
      is_atom(action) and Code.ensure_loaded?(action) and function_exported?(action, :execute, 2)
  end

  def valid?(%__MODULE__{
        name: name,
        conversation_mode: conversation_mode,
        handler: {:call_variables, %VariablesBinding{} = binding}
      }) do
    conversation_mode == :blocking and is_pid(binding.server) and
      VariablesBinding.permitted_tool?(binding, name)
  end

  def valid?(_binding), do: false
end
