defmodule Vxpipe.Gateway.TrustedCall do
  @moduledoc false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    ResolvedCallPlan
  }

  @enforce_keys [:definition, :registries]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          definition: CallDefinition.t(),
          registries: map()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t() | :invalid_config}
  def new(options) when is_list(options) do
    with definition_input when is_map(definition_input) <- Keyword.get(options, :definition),
         resource_id when is_binary(resource_id) <- Keyword.get(options, :resource_id),
         revision when is_integer(revision) and revision > 0 <- Keyword.get(options, :revision),
         capability_profiles when is_map(capability_profiles) <-
           Keyword.get(options, :capability_profiles),
         host_tools when is_map(host_tools) <- Keyword.get(options, :host_tools),
         {:ok, definition} <-
           CallDefinition.new(definition_input,
             resource_id: resource_id,
             revision: revision
           ) do
      {:ok,
       %__MODULE__{
         definition: definition,
         registries: %{capability_profiles: capability_profiles, host_tools: host_tools}
       }}
    else
      nil -> {:error, :invalid_config}
      false -> {:error, :invalid_config}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_config}
    end
  end

  @spec start(t(), keyword(), term()) ::
          {:ok, Vxpipe.CallEngine.Room.Snapshot.t(), Vxpipe.CallEngine.Participant.Snapshot.t()}
          | {:error, Vxpipe.CallEngine.Error.t()}
  def start(%__MODULE__{} = trusted_call, principal, room_id) when is_list(principal) do
    definition = trusted_call.definition

    invocation_input = %{
      call_definition: %{id: definition.resource_id, revision: definition.revision},
      initial_variables: %{},
      transport: %{type: "web"}
    }

    with {:ok, invocation} <-
           CallInvocation.new(invocation_input,
             tenant_id: Keyword.fetch!(principal, :tenant_id),
             actor_id: Keyword.fetch!(principal, :actor_id),
             room_id: room_id
           ),
         {:ok, %ResolvedCallPlan{} = plan} <-
           DefinitionCompiler.compile(definition, invocation, trusted_call.registries),
         {:ok, room} <- CallEngine.start_call(plan),
         entry_caller <- Map.fetch!(plan.participants, plan.entry_caller),
         {:ok, participant} <-
           CallEngine.participant_snapshot(
             plan.tenant_id,
             plan.room_id,
             entry_caller.participant_id
           ) do
      {:ok, room, participant}
    end
  end
end
