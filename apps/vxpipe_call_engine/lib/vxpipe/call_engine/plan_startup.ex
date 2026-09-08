defmodule Vxpipe.CallEngine.PlanStartup do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.Command.JoinParticipant

  alias Vxpipe.CallEngine.{
    Id,
    ResolvedCallPlan,
    SpeechToTextRuntime,
    TextToSpeechRuntime
  }

  @participant_command_timeout_ms 5_000

  @enforce_keys [
    :caller,
    :caller_command,
    :receiver,
    :receiver_command,
    :agent_activation,
    :speech_to_text,
    :text_to_speech
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          caller: ResolvedCallPlan.Participant.t(),
          caller_command: JoinParticipant.t(),
          receiver: ResolvedCallPlan.Participant.t(),
          receiver_command: JoinParticipant.t(),
          agent_activation: keyword(),
          speech_to_text: nil | SpeechToTextRuntime.t(),
          text_to_speech: nil | TextToSpeechRuntime.t()
        }

  @spec new(ResolvedCallPlan.t(), keyword()) :: {:ok, t()} | {:error, atom()}
  def new(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    with {:ok, caller} <- entry_participant(plan, plan.entry_caller, :human),
         {:ok, receiver} <- entry_participant(plan, plan.entry_receiver, :agent),
         {:ok, activation_options} <- agent_activation_options(receiver, options),
         {:ok, speech_to_text} <- speech_to_text_runtime(caller, options),
         {:ok, text_to_speech} <- text_to_speech_runtime(receiver, options),
         {:ok, caller_command} <- participant_command(plan, caller),
         {:ok, receiver_command} <- participant_command(plan, receiver) do
      {:ok,
       %__MODULE__{
         caller: caller,
         caller_command: caller_command,
         receiver: receiver,
         receiver_command: receiver_command,
         agent_activation: activation_options,
         speech_to_text: speech_to_text,
         text_to_speech: text_to_speech
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

  defp speech_to_text_runtime(caller, options) do
    case resolve_provider(caller.capabilities.speech_to_text, options, :speech_to_text) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, provider, settings} ->
        with {transport, transport_options}
             when is_atom(transport) and is_list(transport_options) <-
               Keyword.get(settings, :transport),
             media_ingress when is_list(media_ingress) <-
               Keyword.get(settings, :media_ingress) do
          {:ok,
           %SpeechToTextRuntime{
             provider: provider,
             transport: {transport, transport_options},
             media_ingress: media_ingress
           }}
        else
          _invalid_runtime -> {:error, :unsupported_speech_to_text_configuration}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp text_to_speech_runtime(receiver, options) do
    case resolve_provider(receiver.capabilities.text_to_speech, options, :text_to_speech) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, provider, settings} ->
        with {transport, transport_options}
             when is_atom(transport) and is_list(transport_options) <-
               Keyword.get(settings, :transport),
             maximum_requests when is_integer(maximum_requests) and maximum_requests > 0 <-
               Keyword.get(settings, :maximum_requests) do
          {:ok,
           %TextToSpeechRuntime{
             provider: provider,
             transport: {transport, transport_options},
             maximum_requests: maximum_requests
           }}
        else
          _invalid_runtime -> {:error, :unsupported_text_to_speech_configuration}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp resolve_provider(nil, _options, _kind), do: {:ok, nil}

  defp resolve_provider(
         %CapabilitySelection{provider: provider, options: public_options},
         options,
         kind
       ) do
    settings = Keyword.get(options, kind)

    with settings when is_list(settings) <- settings,
         true <- Keyword.get(settings, :enabled) == true,
         ^provider <- Keyword.get(settings, :provider),
         private_options when is_list(private_options) <-
           Keyword.get(settings, :provider_options),
         {:ok, selected_options} <- selected_options(public_options),
         true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :new, 1),
         {:ok, provider_config} <-
           provider.new(Keyword.merge(private_options, selected_options)) do
      {:ok, {provider, provider_config}, settings}
    else
      _unsupported -> {:error, unsupported_speech_configuration(kind)}
    end
  rescue
    _exception -> {:error, unsupported_speech_configuration(kind)}
  end

  defp selected_options(options) when is_map(options) do
    if Enum.all?(options, fn {key, _value} -> is_atom(key) end) do
      {:ok, Map.to_list(options)}
    else
      {:error, :unsupported_provider_options}
    end
  end

  defp unsupported_speech_configuration(:speech_to_text),
    do: :unsupported_speech_to_text_configuration

  defp unsupported_speech_configuration(:text_to_speech),
    do: :unsupported_text_to_speech_configuration

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
