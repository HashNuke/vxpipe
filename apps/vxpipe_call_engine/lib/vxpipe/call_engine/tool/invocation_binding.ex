defmodule Vxpipe.CallEngine.Tool.InvocationBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding, as: VariablesBinding
  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.PlatformCatalog
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding, as: TransferBinding

  @derive {Inspect, only: [:name, :conversation_mode]}
  @enforce_keys [:name, :conversation_mode, :handler]
  defstruct @enforce_keys ++ [usage_integration_id: nil]

  @type handler ::
          {:host, module()}
          | {:platform, module()}
          | {:participant_transfer, TransferBinding.t()}
          | {:call_variables, VariablesBinding.t()}
          | {:remote_mcp, GenServer.server()}
  @type t :: %__MODULE__{
          name: String.t(),
          conversation_mode: :blocking | :non_blocking,
          handler: handler(),
          usage_integration_id: String.t() | nil
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

  def from_resolved(%ToolBinding{
        name: name,
        type: :platform,
        conversation_mode: conversation_mode,
        action: action
      })
      when is_binary(name) and conversation_mode in [:blocking, :non_blocking] and
             is_atom(action) do
    if PlatformCatalog.action?(action) do
      {:ok,
       %__MODULE__{
         name: name,
         conversation_mode: conversation_mode,
         handler: {:platform, action}
       }}
    else
      {:error, :invalid_binding}
    end
  end

  def from_resolved(%ToolBinding{}), do: {:error, :invalid_binding}

  @spec from_participant_transfer(ToolBinding.t()) ::
          {:ok, t()} | {:error, :invalid_binding}
  def from_participant_transfer(%ToolBinding{
        name: "transfer",
        type: :participant_transfer,
        conversation_mode: :blocking,
        transfer: %TransferBinding{} = binding
      }) do
    {:ok,
     %__MODULE__{
       name: "transfer",
       conversation_mode: :blocking,
       handler: {:participant_transfer, binding}
     }}
  end

  def from_participant_transfer(%ToolBinding{}), do: {:error, :invalid_binding}

  @spec from_remote(ToolBinding.t(), GenServer.server()) ::
          {:ok, t()} | {:error, :invalid_binding}
  def from_remote(
        %ToolBinding{
          name: name,
          type: :mcp,
          conversation_mode: conversation_mode,
          remote: %ResolvedTool{} = remote
        },
        owner
      )
      when is_binary(name) and conversation_mode in [:blocking, :non_blocking] do
    if server_ref?(owner) do
      {:ok,
       %__MODULE__{
         name: name,
         conversation_mode: conversation_mode,
         handler: {:remote_mcp, owner},
         usage_integration_id: remote.integration_id
       }}
    else
      {:error, :invalid_binding}
    end
  end

  def from_remote(%ToolBinding{}, _owner), do: {:error, :invalid_binding}

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
        name: "transfer",
        conversation_mode: :blocking,
        handler: {:participant_transfer, %TransferBinding{}}
      }),
      do: true

  def valid?(%__MODULE__{
        name: name,
        conversation_mode: conversation_mode,
        handler: {:platform, action}
      }) do
    is_binary(name) and name != "" and conversation_mode in [:blocking, :non_blocking] and
      PlatformCatalog.action?(action)
  end

  def valid?(%__MODULE__{
        name: name,
        conversation_mode: conversation_mode,
        handler: {:call_variables, %VariablesBinding{} = binding}
      }) do
    conversation_mode == :blocking and is_pid(binding.server) and
      VariablesBinding.permitted_tool?(binding, name)
  end

  def valid?(%__MODULE__{
        name: name,
        conversation_mode: conversation_mode,
        handler: {:remote_mcp, owner},
        usage_integration_id: integration_id
      }) do
    is_binary(name) and name != "" and conversation_mode in [:blocking, :non_blocking] and
      server_ref?(owner) and is_binary(integration_id) and integration_id != "" and
      byte_size(integration_id) <= 256
  end

  def valid?(_binding), do: false

  defp server_ref?(nil), do: false
  defp server_ref?(server) when is_pid(server) or is_atom(server), do: true
  defp server_ref?({:global, _term}), do: true
  defp server_ref?({:via, module, _term}) when is_atom(module), do: true
  defp server_ref?(_server), do: false
end
