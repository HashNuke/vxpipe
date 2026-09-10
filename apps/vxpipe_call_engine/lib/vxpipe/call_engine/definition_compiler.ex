defmodule Vxpipe.CallEngine.DefinitionCompiler do
  @moduledoc """
  Resolves a validated call definition and invocation through closed registries.
  """

  alias Vxpipe.CallEngine.CallDefinition

  alias Vxpipe.CallEngine.CallDefinition.{CapabilitySelection, ToolSelection}

  alias Vxpipe.CallEngine.{CallInvocation, DefinitionValidation, Id, ResolvedCallPlan}

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    ToolBinding,
    ToolVisibility,
    VariableSection
  }

  @code :call_definition_resolution_failed
  @message "The call definition could not be resolved."

  @spec compile(CallDefinition.t(), CallInvocation.t(), map(), keyword()) ::
          {:ok, ResolvedCallPlan.t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def compile(
        %CallDefinition{} = definition,
        %CallInvocation{} = invocation,
        registries,
        options \\ []
      )
      when is_map(registries) and is_list(options) do
    with :ok <- matching_definition(definition, invocation),
         {:ok, capability_profiles} <- registry(registries, :capability_profiles),
         {:ok, host_tools} <- registry(registries, :host_tools),
         {:ok, call_variables} <-
           resolve_call_variables(definition.call_variables, invocation.initial_variables),
         {:ok, participants} <-
           resolve_participants(definition, capability_profiles, host_tools),
         {:ok, tool_visibility} <-
           resolve_tool_visibility(
             Keyword.get(options, :tool_visibility, definition.tool_visibility),
             participants
           ) do
      {:ok,
       %ResolvedCallPlan{
         definition_id: definition.resource_id,
         definition_revision: definition.revision,
         schema_version: definition.schema_version,
         tenant_id: invocation.tenant_id,
         actor_id: invocation.actor_id,
         call_id: invocation.call_id,
         room_id: invocation.room_id,
         transport: invocation.transport,
         entry_caller: definition.entry_caller,
         entry_receiver: definition.entry_receiver,
         participants: participants,
         call_variables: call_variables,
         tool_visibility: tool_visibility,
         max_duration_ms: definition.max_duration_ms
       }}
    end
  end

  defp resolve_tool_visibility(
         %CallDefinition.ToolVisibility{} = policy,
         participants
       ) do
    overrides =
      Map.new(policy.overrides, fn {definition_key, tool_levels} ->
        participant = Map.fetch!(participants, definition_key)
        {participant.participant_id, tool_levels}
      end)

    {:ok, %ToolVisibility{default: policy.default, overrides: overrides}}
  end

  defp resolve_tool_visibility(_invalid, _participants) do
    invalid(["tool_visibility"], "is not a validated trusted policy")
  end

  defp matching_definition(definition, invocation) do
    cond do
      definition.resource_id != invocation.definition_id ->
        invalid(["call_definition", "id"], "does not match the selected definition")

      definition.revision != invocation.definition_revision ->
        invalid(["call_definition", "revision"], "does not match the selected definition")

      true ->
        :ok
    end
  end

  defp registry(registries, key) do
    case Map.fetch(registries, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _error -> invalid(["registries", Atom.to_string(key)], "is unavailable")
    end
  end

  defp resolve_participants(definition, capability_profiles, host_tools) do
    Enum.reduce_while(definition.participants, {:ok, %{}}, fn {key, participant}, {:ok, acc} ->
      case resolve_participant(
             participant,
             definition.default_capabilities,
             capability_profiles,
             host_tools
           ) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_participant(
         %CallDefinition.Participant{} = participant,
         defaults,
         profiles,
         host_tools
       ) do
    with {:ok, capabilities} <- resolve_capabilities(participant, defaults, profiles),
         {:ok, tools} <- resolve_tools(participant, host_tools) do
      activation_id = if participant.kind == :agent, do: Id.generate(:activation), else: nil

      {:ok,
       %ResolvedCallPlan.Participant{
         definition_key: participant.definition_key,
         participant_id: Id.generate(:participant),
         activation_id: activation_id,
         kind: participant.kind,
         description: participant.description,
         connection: participant.connection,
         prompt: participant.prompt,
         first_message: participant.first_message,
         first_message_text: participant.first_message_text,
         capabilities: capabilities,
         tools: tools,
         transfers: participant.transfers,
         variable_permissions: participant.variable_permissions
       }}
    end
  end

  defp resolve_call_variables(call_variables, initial_variables) do
    with :ok <- validate_initial_variables(call_variables.sections, initial_variables) do
      sections =
        Map.new(call_variables.sections, fn {name, section} ->
          {name,
           %VariableSection{
             name: name,
             schema: section.schema,
             validator: section.validator,
             value: Map.get(initial_variables, name),
             revision: 0
           }}
        end)

      {:ok, %CallVariables{sections: sections}}
    end
  end

  defp validate_initial_variables(sections, initial_variables) do
    Enum.reduce_while(initial_variables, :ok, fn
      {name, value}, :ok when is_binary(name) ->
        case Map.fetch(sections, name) do
          {:ok, section} ->
            case JSV.validate(value, section.validator, cast: false) do
              {:ok, ^value} -> {:cont, :ok}
              {:error, _error} -> {:halt, invalid(["initial_variables", name], "is invalid")}
            end

          :error ->
            {:halt, invalid(["initial_variables", name], "is not a declared section")}
        end

      {_name, _value}, :ok ->
        {:halt, invalid(["initial_variables", "<invalid-key>"], "section names must be strings")}
    end)
  end

  defp resolve_capabilities(participant, defaults, profiles) do
    kinds =
      if participant.kind == :human,
        do: [:speech_to_text],
        else: [:model_inference, :text_to_speech]

    Enum.reduce_while(kinds, {:ok, %ResolvedCallPlan.Capabilities{}}, fn kind, {:ok, acc} ->
      {ref, path} = effective_ref(participant, defaults, kind)

      case resolve_capability(ref, kind, profiles, path, participant.kind) do
        {:ok, selection} -> {:cont, {:ok, put_capability(acc, kind, selection)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp effective_ref(participant, defaults, kind) do
    participant_ref = CallDefinition.Capabilities.ref(participant.capabilities, kind)

    if participant_ref do
      {participant_ref,
       ["participants", participant.definition_key, "capabilities", Atom.to_string(kind)]}
    else
      {CallDefinition.Capabilities.ref(defaults, kind),
       ["defaults", "capabilities", Atom.to_string(kind)]}
    end
  end

  defp resolve_capability(nil, :model_inference, _profiles, path, :agent) do
    invalid(path, "is required for an agent participant")
  end

  defp resolve_capability(nil, _kind, _profiles, _path, _participant_kind), do: {:ok, nil}

  defp resolve_capability(ref, kind, profiles, path, _participant_kind) do
    case Map.fetch(profiles, ref) do
      {:ok, %{kind: ^kind, provider: provider, options: options}}
      when is_atom(provider) and is_map(options) ->
        if DefinitionValidation.private_data?(options) do
          invalid(path, "resolves to private configuration that cannot enter a call plan")
        else
          {:ok,
           %CapabilitySelection{
             kind: kind,
             profile: ref,
             provider: provider,
             options: options
           }}
        end

      {:ok, _wrong_kind_or_shape} ->
        invalid(path, "does not resolve to a valid #{kind} profile")

      :error ->
        invalid(path, "does not resolve to an available capability profile")
    end
  end

  defp put_capability(capabilities, :speech_to_text, selection),
    do: %{capabilities | speech_to_text: selection}

  defp put_capability(capabilities, :model_inference, selection),
    do: %{capabilities | model_inference: selection}

  defp put_capability(capabilities, :text_to_speech, selection),
    do: %{capabilities | text_to_speech: selection}

  defp resolve_tools(%CallDefinition.Participant{kind: :human}, _host_tools), do: {:ok, %{}}

  defp resolve_tools(%CallDefinition.Participant{} = participant, host_tools) do
    Enum.reduce_while(participant.tools, {:ok, %{}}, fn {name, selection}, {:ok, acc} ->
      path = ["participants", participant.definition_key, "tools", name]

      case resolve_tool(selection, host_tools, path) do
        {:ok, binding} -> {:cont, {:ok, Map.put(acc, name, binding)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_tool(%ToolSelection{name: name, type: :host, tool: tool}, host_tools, path) do
    cond do
      name != tool ->
        invalid(path, "must use the static Action name as its local key in this schema subset")

      true ->
        case Map.fetch(host_tools, tool) do
          {:ok, action} when is_atom(action) -> validate_action(name, action, path)
          _error -> invalid(path, "does not resolve to an available host tool")
        end
    end
  end

  defp resolve_tool(%ToolSelection{type: :mcp}, _host_tools, path) do
    invalid(path, "does not resolve to an available remote MCP tool")
  end

  defp validate_action(name, action, path) do
    if Code.ensure_loaded?(action) and function_exported?(action, :definition, 0) and
         function_exported?(action, :execute, 2) do
      definition = action.definition()

      if definition.name == name do
        {:ok, %ToolBinding{name: name, type: :host, action: action}}
      else
        invalid(path, "does not match the registered host tool name")
      end
    else
      invalid(path, "does not implement the host tool contract")
    end
  end

  defp invalid(path, reason), do: DefinitionValidation.invalid(@code, @message, path, reason)
end
