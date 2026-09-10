defmodule Vxpipe.CallEngine.PlanStartup.AgentActivation do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}

  @error_code :unsupported_call_plan
  @error_message "The resolved call plan is not supported by this runtime."

  @spec new(ResolvedCallPlan.t(), ResolvedCallPlan.Participant.t(), keyword()) ::
          {:ok, keyword()} | {:error, Error.t()}
  def new(%ResolvedCallPlan{} = plan, %ResolvedCallPlan.Participant{} = receiver, options)
      when is_list(options) do
    with %CapabilitySelection{provider: :req_llm, options: provider_options} <-
           receiver.capabilities.model_inference,
         {:ok, model} <- agent_model(provider_options),
         owner when is_pid(owner) <- Keyword.get(options, :owner),
         settings when is_list(settings) <- Keyword.get(options, :agent_runtime),
         {:ok, variable_binding} <- variable_binding(plan, receiver, options),
         {:ok, mcp_integrations} <- mcp_integrations(receiver, options),
         {:ok, activation_options} <-
           activation_options(
             Keyword.get(settings, :implementation, :agent_runtime),
             receiver,
             model,
             variable_binding,
             mcp_integrations,
             owner,
             options,
             settings
           ) do
      {:ok, activation_options}
    else
      {:error, %Error{}} = error -> error
      _unsupported -> unsupported_model(receiver)
    end
  rescue
    _exception -> unsupported_model(receiver)
  end

  defp activation_options(
         :agent_runtime,
         receiver,
         model,
         variable_binding,
         mcp_integrations,
         owner,
         options,
         settings
       ) do
    provider_module = Keyword.get(settings, :model_provider)
    provider_options = Keyword.get(settings, :model_provider_options)

    with provider_module when is_atom(provider_module) <- provider_module,
         true <- Code.ensure_loaded?(provider_module),
         true <- function_exported?(provider_module, :new, 1),
         provider_options when is_list(provider_options) <- provider_options,
         {:ok, provider_config} <-
           provider_module.new(Keyword.put(provider_options, :model, model)) do
      {:ok,
       common_options(receiver, variable_binding, mcp_integrations, owner, options, settings) ++
         [
           runtime: :agent_runtime,
           model_provider: provider_module,
           model: provider_config,
           provider: Keyword.get(settings, :model_provider_label, :req_llm),
           tools: receiver.tools
         ]}
    else
      _invalid -> {:error, :unsupported_agent_runtime}
    end
  end

  defp activation_options(
         _implementation,
         _receiver,
         _model,
         _variable_binding,
         _mcp_integrations,
         _owner,
         _options,
         _settings
       ),
       do: {:error, :unsupported_agent_runtime}

  defp common_options(receiver, variable_binding, mcp_integrations, owner, options, settings) do
    base = [
      activation_id: receiver.activation_id,
      agent_participant_id: receiver.participant_id,
      tool_invocation_timeout_ms: Keyword.fetch!(settings, :tool_invocation_timeout_ms),
      maximum_tool_invocations: Keyword.fetch!(settings, :maximum_tool_invocations),
      owner: owner,
      system_prompt: receiver.prompt,
      variable_binding: variable_binding,
      maximum_completed_requests: Keyword.fetch!(settings, :maximum_completed_requests),
      maximum_output_bytes: Keyword.fetch!(settings, :maximum_output_bytes),
      maximum_pending_requests: Keyword.fetch!(settings, :maximum_pending_requests),
      maximum_tool_result_bytes: Keyword.fetch!(settings, :maximum_tool_result_bytes),
      request_timeout_ms: Keyword.fetch!(settings, :request_timeout_ms)
    ]

    base
    |> put_optional(:mcp_integrations, mcp_integrations)
    |> put_optional(
      :remote_mcp_connection_provider,
      Keyword.get(options, :remote_mcp_connection_provider)
    )
    |> put_optional(
      :remote_mcp_protocol_client,
      Keyword.get(options, :remote_mcp_protocol_client)
    )
  end

  defp mcp_integrations(receiver, options) do
    remote_bindings =
      Enum.flat_map(receiver.tools, fn
        {name, %ToolBinding{type: :mcp, remote: remote}} -> [{name, remote}]
        _binding -> []
      end)

    case {remote_bindings, Keyword.get(options, :mcp_integrations)} do
      {[], _integrations} ->
        {:ok, nil}

      {bindings, %IntegrationCatalog{} = integrations} ->
        case unavailable_remote_binding(bindings, integrations) do
          nil ->
            {:ok, integrations}

          name ->
            unsupported(
              ["participants", receiver.definition_key, "tools", name],
              "pinned remote MCP generation is no longer available"
            )
        end

      {_bindings, _integrations} ->
        {name, _remote} = List.first(remote_bindings)

        unsupported(
          ["participants", receiver.definition_key, "tools", name],
          "remote MCP integrations are unavailable"
        )
    end
  end

  defp unavailable_remote_binding(bindings, integrations) do
    Enum.find_value(bindings, fn {name, remote} ->
      case IntegrationCatalog.checkout(integrations, remote) do
        {:ok, _integration} -> nil
        {:error, _reason} -> name
      end
    end)
  end

  defp variable_binding(plan, receiver, options) do
    cond do
      map_size(receiver.variable_permissions.grants) == 0 ->
        {:ok, nil}

      Keyword.get(options, :validation_only, false) ->
        {:ok, nil}

      true ->
        build_variable_binding(plan, receiver, options)
    end
  end

  defp build_variable_binding(plan, receiver, options) do
    case {Keyword.get(options, :call_variables), Keyword.get(options, :incarnation_id)} do
      {server, incarnation_id} when is_pid(server) and is_binary(incarnation_id) ->
        {:ok, Binding.new(server, plan, receiver, incarnation_id)}

      _invalid ->
        unsupported(["call_variables", "sections"], "runtime binding is unavailable")
    end
  end

  defp agent_model(%{model: model} = options)
       when map_size(options) == 1 and is_binary(model),
       do: nonempty_model(model)

  defp agent_model(%{"model" => model} = options)
       when map_size(options) == 1 and is_binary(model),
       do: nonempty_model(model)

  defp agent_model(_unsupported), do: {:error, :unsupported_provider_options}

  defp nonempty_model(model) do
    if String.trim(model) == "", do: {:error, :invalid_model}, else: {:ok, model}
  end

  defp unsupported_model(receiver) do
    unsupported(
      ["participants", receiver.definition_key, "capabilities", "model_inference"],
      "must select a supported ReqLLM model profile"
    )
  end

  defp unsupported(path, reason) do
    {:error,
     Error.new(@error_code, @error_message, details: %{"path" => path, "reason" => reason})}
  end

  defp put_optional(options, _key, nil), do: options
  defp put_optional(options, key, value), do: Keyword.put(options, key, value)
end
