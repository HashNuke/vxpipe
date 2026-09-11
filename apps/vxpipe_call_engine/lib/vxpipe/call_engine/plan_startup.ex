defmodule Vxpipe.CallEngine.PlanStartup do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.CallDefinition.ConnectionIntent
  alias Vxpipe.CallEngine.CallDefinition.OpeningAudio
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.PlanStartup.AgentActivation, as: AgentActivationOptions
  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.PlanStartup.HumanDestination
  alias Vxpipe.CallEngine.OpeningAudio.Settings, as: OpeningAudioSettings
  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.Tool.PlatformCatalog

  alias Vxpipe.CallEngine.{
    Error,
    Id,
    ResolvedCallPlan,
    SpeechToTextRuntime,
    TextToSpeechRuntime
  }

  @participant_command_timeout_ms 5_000
  @error_code :unsupported_call_plan
  @error_message "The resolved call plan is not supported by this runtime."

  @enforce_keys [
    :caller,
    :caller_command,
    :receiver,
    :receiver_command,
    :agent_activation,
    :speech_to_text_runtimes,
    :text_to_speech
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          caller: ResolvedCallPlan.Participant.t(),
          caller_command: JoinParticipant.t(),
          receiver: ResolvedCallPlan.Participant.t(),
          receiver_command: JoinParticipant.t(),
          agent_activation: nil | keyword(),
          speech_to_text_runtimes: %{
            required(String.t()) => nil | SpeechToTextRuntime.t()
          },
          text_to_speech: nil | TextToSpeechRuntime.t()
        }

  @spec validate(ResolvedCallPlan.t(), keyword()) ::
          :ok | {:error, Error.t()}
  def validate(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    case new(plan, Keyword.put(options, :validation_only, true)) do
      {:ok, %__MODULE__{}} -> :ok
      {:error, %Error{}} = error -> error
    end
  end

  @spec new(ResolvedCallPlan.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    with {:ok, caller} <- entry_participant(plan, :entry_caller, plan.entry_caller, :human),
         {:ok, receiver} <-
           entry_participant(plan, :entry_receiver, plan.entry_receiver, [:human, :agent]),
         :ok <- supported_features(plan, caller, receiver),
         {:ok, activation_options} <- agent_activation_options(plan, receiver, options),
         {:ok, speech_to_text_runtimes} <-
           speech_to_text_runtimes([caller, receiver], plan.opening_audio, options),
         {:ok, text_to_speech} <- text_to_speech_runtime(receiver, options),
         :ok <- supported_opening_audio(plan.opening_audio, text_to_speech, options),
         {:ok, caller_command} <- participant_command(plan, caller),
         {:ok, receiver_command} <- participant_command(plan, receiver) do
      {:ok,
       %__MODULE__{
         caller: caller,
         caller_command: caller_command,
         receiver: receiver,
         receiver_command: receiver_command,
         agent_activation: activation_options,
         speech_to_text_runtimes: speech_to_text_runtimes,
         text_to_speech: text_to_speech
       }}
    end
  end

  @spec agent_destination(
          ResolvedCallPlan.t(),
          ResolvedCallPlan.Participant.t(),
          keyword()
        ) :: {:ok, AgentDestination.t()} | {:error, Error.t()}
  def agent_destination(
        %ResolvedCallPlan{} = plan,
        %ResolvedCallPlan.Participant{kind: :agent} = participant,
        options
      )
      when is_list(options) do
    with {:ok, activation_options} <- agent_activation_options(plan, participant, options),
         {:ok, text_to_speech} <- text_to_speech_runtime(participant, options),
         {:ok, command} <- participant_command(plan, participant) do
      {:ok,
       %AgentDestination{
         participant: participant,
         command: command,
         agent_activation: activation_options,
         text_to_speech: text_to_speech
       }}
    end
  end

  def agent_destination(
        %ResolvedCallPlan{},
        %ResolvedCallPlan.Participant{} = participant,
        options
      )
      when is_list(options) do
    unsupported(
      ["participants", participant.definition_key, "type"],
      "must be an agent participant"
    )
  end

  @spec human_destination(
          ResolvedCallPlan.t(),
          ResolvedCallPlan.Participant.t()
        ) :: {:ok, HumanDestination.t()} | {:error, Error.t()}
  def human_destination(
        %ResolvedCallPlan{} = plan,
        %ResolvedCallPlan.Participant{
          kind: :human,
          connection: %ConnectionIntent{
            service: :web,
            mode: :receive,
            admission: :transfer
          }
        } = participant
      ) do
    with {:ok, command} <- participant_command(plan, participant) do
      {:ok, %HumanDestination{participant: participant, command: command}}
    end
  end

  def human_destination(
        %ResolvedCallPlan{},
        %ResolvedCallPlan.Participant{} = participant
      ) do
    unsupported(
      ["participants", participant.definition_key, "connection"],
      "must be a web receive/transfer human participant"
    )
  end

  defp entry_participant(plan, field, definition_key, expected_kinds) do
    expected_kinds = List.wrap(expected_kinds)

    case Map.fetch(plan.participants, definition_key) do
      {:ok, %ResolvedCallPlan.Participant{} = participant} ->
        if participant.kind in expected_kinds,
          do: {:ok, participant},
          else: unsupported_entry(field)

      _missing_or_wrong_kind ->
        unsupported_entry(field)
    end
  end

  defp unsupported_entry(field) do
    unsupported([Atom.to_string(field)], "must resolve to the supported participant type")
  end

  defp supported_features(plan, caller, receiver) do
    with :ok <- supported_transport(plan),
         :ok <- supported_connection(caller),
         :ok <- supported_receiver(receiver),
         :ok <- supported_tools(plan) do
      :ok
    end
  end

  defp supported_receiver(%ResolvedCallPlan.Participant{kind: :agent} = receiver) do
    supported_first_message(receiver)
  end

  defp supported_receiver(%ResolvedCallPlan.Participant{kind: :human} = receiver) do
    supported_connection(receiver)
  end

  defp supported_transport(%ResolvedCallPlan{transport: :web}), do: :ok

  defp supported_transport(_plan) do
    unsupported(["transport", "type"], "only web transport is supported")
  end

  defp supported_connection(%ResolvedCallPlan.Participant{
         connection: %ConnectionIntent{service: :web, mode: :receive, admission: :start_call}
       }),
       do: :ok

  defp supported_connection(caller) do
    unsupported(
      ["participants", caller.definition_key, "connection"],
      "only web receive/start_call connection intent is supported"
    )
  end

  defp supported_first_message(%ResolvedCallPlan.Participant{
         first_message: mode,
         first_message_text: nil
       })
       when mode in [:wait_for_input, :generated],
       do: :ok

  defp supported_first_message(%ResolvedCallPlan.Participant{
         first_message: :fixed,
         first_message_text: text
       })
       when is_binary(text),
       do: :ok

  defp supported_first_message(receiver) do
    unsupported(
      ["participants", receiver.definition_key, "first_message", "mode"],
      "must be a supported first-message mode"
    )
  end

  defp supported_tools(plan) do
    Enum.reduce_while(plan.participants, :ok, fn {participant_key, participant}, :ok ->
      case Enum.find(participant.tools, fn {_name, binding} ->
             not supported_tool_binding?(binding)
           end) do
        nil ->
          {:cont, :ok}

        {name, _binding} ->
          {:halt,
           unsupported(
             ["participants", participant_key, "tools", name],
             "must be a resolved platform, host, or remote MCP tool"
           )}
      end
    end)
  end

  defp supported_tool_binding?(%ResolvedCallPlan.ToolBinding{type: :host, action: action})
       when is_atom(action),
       do: true

  defp supported_tool_binding?(%ResolvedCallPlan.ToolBinding{type: :platform, action: action}),
    do: PlatformCatalog.action?(action)

  defp supported_tool_binding?(%ResolvedCallPlan.ToolBinding{
         type: :mcp,
         remote: %ResolvedTool{}
       }),
       do: true

  defp supported_tool_binding?(%ResolvedCallPlan.ToolBinding{
         type: :participant_transfer,
         transfer: %Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding{}
       }),
       do: true

  defp supported_tool_binding?(_binding), do: false

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
      {:ok, command} ->
        {:ok, command}

      {:error, _error} ->
        unsupported(
          ["participants", participant.definition_key],
          "cannot be converted to a runtime participant"
        )
    end
  end

  defp speech_to_text_runtimes(participants, opening_audio, options) do
    Enum.reduce_while(participants, {:ok, %{}}, fn participant, {:ok, runtimes} ->
      case speech_to_text_runtime(participant, opening_audio, options) do
        {:ok, runtime} ->
          {:cont, {:ok, Map.put(runtimes, participant.participant_id, runtime)}}

        {:error, %Error{}} = error ->
          {:halt, error}
      end
    end)
  end

  defp agent_activation_options(
         %ResolvedCallPlan{},
         %ResolvedCallPlan.Participant{kind: :human},
         options
       )
       when is_list(options),
       do: {:ok, nil}

  defp agent_activation_options(plan, receiver, options) do
    AgentActivationOptions.new(plan, receiver, options)
  end

  defp speech_to_text_runtime(caller, opening_audio, options) do
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
             media_ingress:
               Keyword.put(
                 media_ingress,
                 :input_admission,
                 if(opening_audio == nil, do: :open, else: :closed)
               )
           }}
        else
          _invalid_runtime -> unsupported_speech_configuration(caller, :speech_to_text)
        end

      {:error, _reason} ->
        unsupported_speech_configuration(caller, :speech_to_text)
    end
  end

  defp supported_opening_audio(nil, _text_to_speech, _options), do: :ok

  defp supported_opening_audio(
         %OpeningAudio{type: :text},
         %TextToSpeechRuntime{},
         _options
       ),
       do: :ok

  defp supported_opening_audio(%OpeningAudio{type: :text}, nil, _options) do
    unsupported(["opening_audio"], "text opening audio requires text-to-speech")
  end

  defp supported_opening_audio(%OpeningAudio{type: :file_url}, _text_to_speech, options) do
    case Keyword.get(options, :opening_audio) do
      %OpeningAudioSettings{} -> :ok
      _invalid -> unsupported(["opening_audio"], "file opening audio is not configured")
    end
  end

  defp text_to_speech_runtime(receiver, options) do
    case resolve_provider(receiver.capabilities.text_to_speech, options, :text_to_speech) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {provider_module, provider_config} = provider, settings} ->
        with {transport, transport_options}
             when is_atom(transport) and is_list(transport_options) <-
               Keyword.get(settings, :transport),
             maximum_requests when is_integer(maximum_requests) and maximum_requests > 0 <-
               Keyword.get(settings, :maximum_requests),
             asset_cache_identity when is_map(asset_cache_identity) <-
               provider_module.asset_cache_identity(provider_config) do
          {:ok,
           %TextToSpeechRuntime{
             asset_cache_identity: asset_cache_identity,
             provider: provider,
             transport: {transport, transport_options},
             maximum_requests: maximum_requests
           }}
        else
          _invalid_runtime -> unsupported_speech_configuration(receiver, :text_to_speech)
        end

      {:error, _reason} ->
        unsupported_speech_configuration(receiver, :text_to_speech)
    end
  end

  defp resolve_provider(nil, _options, _kind), do: {:ok, nil}

  defp resolve_provider(
         %CapabilitySelection{provider: provider, options: public_options},
         options,
         kind
       ) do
    with {:ok, settings} <- provider_settings(Keyword.get(options, kind), provider),
         true <- Keyword.get(settings, :enabled) == true,
         private_options when is_list(private_options) <-
           Keyword.get(settings, :provider_options),
         {:ok, selected_options} <- selected_options(public_options),
         true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :new, 1),
         {:ok, provider_config} <-
           provider.new(Keyword.merge(private_options, selected_options)) do
      {:ok, {provider, provider_config}, settings}
    else
      _unsupported -> {:error, unsupported_speech_configuration_reason(kind)}
    end
  rescue
    _exception -> {:error, unsupported_speech_configuration_reason(kind)}
  end

  defp provider_settings(settings, provider) when is_list(settings) do
    if Keyword.get(settings, :provider) == provider do
      {:ok, settings}
    else
      case Keyword.get(settings, :providers, %{}) do
        providers when is_map(providers) ->
          case Map.fetch(providers, provider) do
            {:ok, provider_settings} when is_list(provider_settings) ->
              {:ok, provider_settings}

            _missing_or_invalid ->
              {:error, :provider_not_configured}
          end

        _invalid_registry ->
          {:error, :provider_not_configured}
      end
    end
  end

  defp provider_settings(_settings, _provider), do: {:error, :provider_not_configured}

  defp selected_options(options) when is_map(options) do
    if Enum.all?(options, fn {key, _value} -> is_atom(key) end) do
      {:ok, Map.to_list(options)}
    else
      {:error, :unsupported_provider_options}
    end
  end

  defp unsupported_speech_configuration_reason(:speech_to_text),
    do: :unsupported_speech_to_text_configuration

  defp unsupported_speech_configuration_reason(:text_to_speech),
    do: :unsupported_text_to_speech_configuration

  defp unsupported_speech_configuration(participant, kind) do
    unsupported(
      ["participants", participant.definition_key, "capabilities", Atom.to_string(kind)],
      "must select a capability profile supported by the configured runtime"
    )
  end

  defp unsupported(path, reason) do
    {:error,
     Error.new(@error_code, @error_message, details: %{"path" => path, "reason" => reason})}
  end
end
