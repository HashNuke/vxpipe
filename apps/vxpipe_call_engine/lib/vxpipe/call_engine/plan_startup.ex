defmodule Vxpipe.CallEngine.PlanStartup do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.{Id, ResolvedCallPlan}

  @participant_command_timeout_ms 5_000

  @enforce_keys [
    :caller,
    :caller_command,
    :receiver,
    :receiver_command,
    :agent_activation
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          caller: ResolvedCallPlan.Participant.t(),
          caller_command: JoinParticipant.t(),
          receiver: ResolvedCallPlan.Participant.t(),
          receiver_command: JoinParticipant.t(),
          agent_activation: keyword()
        }

  @spec new(ResolvedCallPlan.t(), keyword()) :: {:ok, t()} | {:error, atom()}
  def new(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    with {:ok, caller} <- entry_participant(plan, plan.entry_caller, :human),
         {:ok, receiver} <- entry_participant(plan, plan.entry_receiver, :agent),
         {:ok, activation_options} <- agent_activation_options(receiver, options),
         {:ok, caller_command} <- participant_command(plan, caller),
         {:ok, receiver_command} <- participant_command(plan, receiver) do
      {:ok,
       %__MODULE__{
         caller: caller,
         caller_command: caller_command,
         receiver: receiver,
         receiver_command: receiver_command,
         agent_activation: activation_options
       }}
    end
  end

  defp entry_participant(plan, definition_key, kind) do
    case Map.fetch(plan.participants, definition_key) do
      {:ok, %ResolvedCallPlan.Participant{kind: ^kind} = participant} ->
        {:ok, participant}

      _missing_or_wrong_kind ->
        {:error, :invalid_entry_participant}
    end
  end

  defp participant_command(plan, participant) do
    case JoinParticipant.new(
           tenant_id: plan.tenant_id,
           actor_id: plan.actor_id,
           room_id: plan.room_id,
           participant_id: participant.participant_id,
           role: participant.kind,
           deadline:
             DateTime.add(DateTime.utc_now(), @participant_command_timeout_ms, :millisecond),
           id: Id.generate(:command)
         ) do
      {:ok, command} -> {:ok, command}
      {:error, _error} -> {:error, :invalid_participant}
    end
  end

  defp agent_activation_options(receiver, options) do
    with %CapabilitySelection{provider: :req_llm, options: provider_options} <-
           receiver.capabilities.model_inference,
         {:ok, model} <- agent_model(provider_options),
         owner when is_pid(owner) <- Keyword.get(options, :owner),
         request_options when is_list(request_options) <-
           Keyword.get(options, :agent_request_options, []),
         settings when is_list(settings) <- Keyword.get(options, :agent_runtime) do
      tools =
        receiver.tools
        |> Map.values()
        |> Enum.sort_by(& &1.name)
        |> Enum.map(& &1.action)

      {:ok,
       [
         activation_id: receiver.activation_id,
         agent_participant_id: receiver.participant_id,
         owner: owner,
         system_prompt: receiver.prompt,
         tools: tools,
         maximum_completed_requests: Keyword.fetch!(settings, :maximum_completed_requests),
         maximum_output_bytes: Keyword.fetch!(settings, :maximum_output_bytes),
         maximum_pending_requests: Keyword.fetch!(settings, :maximum_pending_requests),
         maximum_tool_result_bytes: Keyword.fetch!(settings, :maximum_tool_result_bytes),
         request_options: Keyword.put(request_options, :model, model),
         request_timeout_ms: Keyword.fetch!(settings, :request_timeout_ms)
       ]}
    else
      _unsupported -> {:error, :unsupported_agent_configuration}
    end
  rescue
    _exception -> {:error, :unsupported_agent_configuration}
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
end
