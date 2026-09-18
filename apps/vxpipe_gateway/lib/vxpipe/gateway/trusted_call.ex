defmodule Vxpipe.Gateway.TrustedCall do
  @moduledoc false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    ResolvedCallPlan
  }

  alias Vxpipe.CallEngine.CallSpec.ToolVisibility

  @derive {Inspect, except: [:initial_variables]}
  @enforce_keys [:call_spec, :registries, :initial_variables]
  defstruct @enforce_keys ++ [tool_visibility_override: nil]

  @type t :: %__MODULE__{
          call_spec: CallSpec.t(),
          registries: map(),
          initial_variables: map(),
          tool_visibility_override: nil | ToolVisibility.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t() | :invalid_config}
  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         [] <-
           Keyword.keys(options) --
             [
               :call_spec,
               :resource_id,
               :revision,
               :host_tools,
               :initial_variables,
               :tool_visibility,
               :tool_visibility_overrides
             ],
         call_spec_input when is_map(call_spec_input) <- Keyword.get(options, :call_spec),
         resource_id when is_binary(resource_id) <- Keyword.get(options, :resource_id),
         revision when is_integer(revision) and revision > 0 <- Keyword.get(options, :revision),
         host_tools when is_map(host_tools) <- Keyword.get(options, :host_tools),
         initial_variables when is_map(initial_variables) <-
           Keyword.get(options, :initial_variables, %{}),
         {:ok, call_spec} <-
           CallSpec.new(call_spec_input,
             resource_id: resource_id,
             revision: revision
           ),
         {:ok, tool_visibility_override} <- tool_visibility_override(options, call_spec) do
      {:ok,
       %__MODULE__{
         call_spec: call_spec,
         registries: %{host_tools: host_tools},
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
    call_spec = trusted_call.call_spec

    invocation_input = %{
      call_spec: %{id: call_spec.resource_id, revision: call_spec.revision},
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
           CallSpecCompiler.compile(
             call_spec,
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

  defp tool_visibility_override(options, call_spec) do
    if Keyword.has_key?(options, :tool_visibility) or
         Keyword.has_key?(options, :tool_visibility_overrides) do
      ToolVisibility.new(
        Keyword.get(options, :tool_visibility, "hidden"),
        Keyword.get(options, :tool_visibility_overrides, %{}),
        call_spec.participants
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
