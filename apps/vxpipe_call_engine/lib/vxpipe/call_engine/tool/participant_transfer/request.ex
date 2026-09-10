defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer.Request do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

  @derive {Inspect, only: [:source_definition_key, :destination_definition_key]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :source_definition_key,
    :source_participant_id,
    :source_activation_id,
    :source_capability,
    :caller_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :tool_call_id,
    :destination_definition_key,
    :destination_participant_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_definition_key: String.t(),
          source_participant_id: String.t(),
          source_activation_id: String.t(),
          source_capability: pid(),
          caller_participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          tool_call_id: String.t(),
          destination_definition_key: String.t(),
          destination_participant_id: String.t()
        }

  @spec new(Binding.t(), map(), Context.t()) :: {:ok, t()} | {:error, :rejected}
  def new(
        %Binding{} = binding,
        %{"destination" => destination} = arguments,
        %Context{} = context
      )
      when map_size(arguments) == 1 and is_binary(destination) do
    with true <- context.agent_participant_id == binding.source_participant_id,
         tool_call_id when is_binary(tool_call_id) <- context.tool_call_id,
         {:ok, target} <- Map.fetch(binding.targets, destination),
         source_capability when is_pid(source_capability) <-
           AgentActivationSupervisor.whereis_child(binding.source_activation_id, :coordinator) do
      {:ok,
       %__MODULE__{
         tenant_id: context.tenant_id,
         room_id: context.room_id,
         incarnation_id: context.incarnation_id,
         source_definition_key: binding.source_definition_key,
         source_participant_id: binding.source_participant_id,
         source_activation_id: binding.source_activation_id,
         source_capability: source_capability,
         caller_participant_id: context.source_participant_id,
         connection_id: context.connection_id,
         command_id: context.command_id,
         correlation_id: context.correlation_id,
         tool_call_id: tool_call_id,
         destination_definition_key: target.definition_key,
         destination_participant_id: target.participant_id
       }}
    else
      _invalid_or_stale -> {:error, :rejected}
    end
  end

  def new(%Binding{}, _arguments, %Context{}), do: {:error, :rejected}
end
