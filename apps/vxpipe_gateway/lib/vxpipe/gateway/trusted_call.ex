defmodule Vxpipe.Gateway.TrustedCall do
  @moduledoc false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    ResolvedCallPlan
  }

  alias Vxpipe.CallEngine.CallDefinition.ToolVisibility

  @derive {Inspect, except: [:initial_variables]}
  @enforce_keys [:definition, :registries, :initial_variables]
  defstruct @enforce_keys ++ [tool_visibility_override: nil]

  @type t :: %__MODULE__{
          definition: CallDefinition.t(),
          registries: map(),
          initial_variables: map(),
          tool_visibility_override: nil | ToolVisibility.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t() | :invalid_config}
  def new(options) when is_list(options) do
    with definition_input when is_map(definition_input) <- Keyword.get(options, :definition),
         resource_id when is_binary(resource_id) <- Keyword.get(options, :resource_id),
         revision when is_integer(revision) and revision > 0 <- Keyword.get(options, :revision),
         capability_profiles when is_map(capability_profiles) <-
           Keyword.get(options, :capability_profiles),
         host_tools when is_map(host_tools) <- Keyword.get(options, :host_tools),
         initial_variables when is_map(initial_variables) <-
           Keyword.get(options, :initial_variables, %{}),
         {:ok, definition} <-
           CallDefinition.new(definition_input,
             resource_id: resource_id,
             revision: revision
           ),
         {:ok, tool_visibility_override} <- tool_visibility_override(options, definition) do
      {:ok,
       %__MODULE__{
         definition: definition,
         registries: %{capability_profiles: capability_profiles, host_tools: host_tools},
         initial_variables: initial_variables,
         tool_visibility_override: tool_visibility_override
       }}
    else
      nil -> {:error, :invalid_config}
      false -> {:error, :invalid_config}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_config}
    end
  end

  @spec start(t(), keyword(), term()) ::
          {:ok, Vxpipe.CallEngine.Room.Snapshot.t(), Vxpipe.CallEngine.Participant.Snapshot.t(),
           Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.t()}
          | {:error, Vxpipe.CallEngine.Error.t()}
  def start(%__MODULE__{} = trusted_call, principal, room_id) when is_list(principal) do
    definition = trusted_call.definition

    invocation_input = %{
      call_definition: %{id: definition.resource_id, revision: definition.revision},
      initial_variables: trusted_call.initial_variables,
      transport: %{type: "web"}
    }

    with {:ok, invocation} <-
           CallInvocation.new(invocation_input,
             tenant_id: Keyword.fetch!(principal, :tenant_id),
             actor_id: Keyword.fetch!(principal, :actor_id),
             room_id: room_id
           ),
         {:ok, %ResolvedCallPlan{} = plan} <-
           DefinitionCompiler.compile(
             definition,
             invocation,
             trusted_call.registries,
             compiler_options(trusted_call)
           ),
         {:ok, room} <- CallEngine.start_call(plan),
         entry_caller <- Map.fetch!(plan.participants, plan.entry_caller),
         {:ok, participant} <-
           CallEngine.participant_snapshot(
             plan.tenant_id,
             plan.room_id,
             entry_caller.participant_id
           ) do
      {:ok, room, participant, plan.tool_visibility}
    end
  end

  defp tool_visibility_override(options, definition) do
    if Keyword.has_key?(options, :tool_visibility) or
         Keyword.has_key?(options, :tool_visibility_overrides) do
      ToolVisibility.new(
        Keyword.get(options, :tool_visibility, "hidden"),
        Keyword.get(options, :tool_visibility_overrides, %{}),
        definition.participants
      )
    else
      {:ok, nil}
    end
  end

  defp compiler_options(%__MODULE__{tool_visibility_override: nil}), do: []

  defp compiler_options(%__MODULE__{tool_visibility_override: policy}) do
    [tool_visibility: policy]
  end
end
