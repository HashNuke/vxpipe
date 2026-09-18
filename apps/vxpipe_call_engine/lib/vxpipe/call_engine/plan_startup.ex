defmodule Vxpipe.CallEngine.PlanStartup do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CallSpec.ConnectionIntent
  alias Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.PlanStartup.AgentActivation, as: AgentActivationOptions
  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.PlanStartup.HumanDestination
  alias Vxpipe.CallEngine.OpeningAudio.Settings, as: OpeningAudioSettings
  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.Tool.PlatformCatalog
  alias Vxpipe.CallEngine.Usage.ProviderContext

  alias Vxpipe.CallEngine.{
    Error,
    CapabilityCatalog,
    CredentialSource,
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
    with :ok <- current_plan(plan),
         {:ok, entries} <- entries(plan) do
      supported_configuration(entries, options)
    end
  end

  defp supported_configuration(entries, options) do
    with :ok <- supported_model(entries.receiver),
         {:ok, _integrations} <-
           AgentActivationOptions.mcp_integrations(entries.receiver, options) do
      for participant <- [entries.caller, entries.receiver],
          kind <- [:speech_to_text, :text_to_speech],
          reduce: :ok do
        :ok -> supported_speech(participant, kind, options)
        error -> error
      end
    end
  end

  defp supported_model(%{kind: :human}), do: :ok

  defp supported_model(%{
         capabilities: %{model_inference: %CapabilitySelection{provider: provider}}
       })
       when provider in ["google", "zenmux", "fixture"],
       do: :ok

  defp supported_model(participant),
    do: unsupported_speech_configuration(participant, :model_inference)

  defp supported_speech(participant, kind, options) do
    selection = Map.fetch!(participant.capabilities, kind)

    case selection do
      nil ->
        :ok

      %CapabilitySelection{} = selection ->
        with {:ok, provider} <- CapabilityCatalog.adapter(selection),
             {:ok, settings} <- provider_settings(Keyword.get(options, kind), provider),
             true <- Keyword.get(settings, :enabled) == true do
          :ok
        else
          _unsupported -> unsupported_speech_configuration(participant, kind)
        end
    end
  end

  def entries(%ResolvedCallPlan{} = plan) do
    with {:ok, caller} <- entry_participant(plan, :entry_caller, plan.entry_caller, :human),
         {:ok, receiver} <-
           entry_participant(plan, :entry_receiver, plan.entry_receiver, [:human, :agent]),
         :ok <- supported_features(plan, caller, receiver),
         {:ok, caller_command} <- participant_command(plan, caller),
         {:ok, receiver_command} <- participant_command(plan, receiver) do
      {:ok,
       %{
         caller: caller,
         receiver: receiver,
         caller_command: caller_command,
         receiver_command: receiver_command
       }}
    end
  end

  @spec new(ResolvedCallPlan.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    with :ok <- current_plan(plan),
         {:ok, entries} <- entries(plan),
         %{caller: caller, receiver: receiver} = entries,
         {:ok, activation_options} <- agent_activation_options(plan, receiver, options),
         {:ok, speech_to_text_runtimes} <-
           speech_to_text_runtimes(plan, [caller, receiver], plan.opening_audio, options),
         {:ok, text_to_speech} <- text_to_speech_runtime(plan, receiver, options) do
      {:ok,
       %__MODULE__{
         caller: caller,
         caller_command: entries.caller_command,
         receiver: receiver,
         receiver_command: entries.receiver_command,
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
         {:ok, text_to_speech} <- text_to_speech_runtime(plan, participant, options),
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
      ["participants", participant.call_spec_key, "type"],
      "must be an agent participant"
    )
  end

  @spec human_destination(
          ResolvedCallPlan.t(),
          ResolvedCallPlan.Participant.t(),
          keyword()
        ) :: {:ok, HumanDestination.t()} | {:error, Error.t()}
  def human_destination(plan, participant, options \\ [])

  def human_destination(
        %ResolvedCallPlan{} = plan,
        %ResolvedCallPlan.Participant{
          kind: :human,
          connection: %ConnectionIntent{
            service: :web,
            mode: :receive,
            admission: :transfer
          }
        } = participant,
        options
      ) do
    build_human_destination(plan, participant, options)
  end

  def human_destination(
        %ResolvedCallPlan{} = plan,
        %ResolvedCallPlan.Participant{
          kind: :human,
          connection: %ConnectionIntent{
            service: service,
            mode: :dial,
            admission: :transfer
          }
        } = participant,
        options
      )
      when is_binary(service) do
    build_human_destination(plan, participant, options)
  end

  def human_destination(
        %ResolvedCallPlan{},
        %ResolvedCallPlan.Participant{} = participant,
        _options
      ) do
    unsupported(
      ["participants", participant.call_spec_key, "connection"],
      "must be a supported receive/transfer or dial/transfer human participant"
    )
  end

  defp build_human_destination(plan, participant, options) do
    with {:ok, command} <- participant_command(plan, participant),
         {:ok, speech_to_text} <- speech_to_text_runtime(plan, participant, nil, options) do
      {:ok,
       %HumanDestination{
         participant: participant,
         command: command,
         speech_to_text: speech_to_text
       }}
    end
  end

  defp entry_participant(plan, field, call_spec_key, expected_kinds) do
    expected_kinds = List.wrap(expected_kinds)

    case Map.fetch(plan.participants, call_spec_key) do
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
         :ok <- supported_tools(plan),
         :ok <- supported_opening(plan.opening_audio) do
      :ok
    end
  end

  defp supported_opening(nil), do: :ok
  defp supported_opening(%OpeningAudio{type: :file_url}), do: :ok

  defp supported_opening(%OpeningAudio{type: :text, text_to_speech: %CapabilitySelection{}}),
    do: :ok

  defp supported_opening(_invalid),
    do:
      unsupported(
        ["opening_audio", "text_to_speech"],
        "requires its own inline text-to-speech selection"
      )

  defp supported_receiver(%ResolvedCallPlan.Participant{kind: :agent} = receiver) do
    supported_first_message(receiver)
  end

  defp supported_receiver(%ResolvedCallPlan.Participant{kind: :human} = receiver) do
    supported_connection(receiver)
  end

  defp supported_transport(%ResolvedCallPlan{transport: :web}), do: :ok
  defp supported_transport(%ResolvedCallPlan{transport: :telephony}), do: :ok

  defp supported_transport(_plan) do
    unsupported(["transport", "type"], "must be a supported transport")
  end

  defp supported_connection(%ResolvedCallPlan.Participant{
         connection: %ConnectionIntent{service: :web, mode: :receive, admission: :start_call}
       }),
       do: :ok

  defp supported_connection(%ResolvedCallPlan.Participant{
         connection: %ConnectionIntent{
           service: service,
           mode: :receive,
           admission: :start_call
         }
       })
       when is_binary(service),
       do: :ok

  defp supported_connection(caller) do
    unsupported(
      ["participants", caller.call_spec_key, "connection"],
      "must be a supported receive/start_call connection intent"
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
      ["participants", receiver.call_spec_key, "first_message", "mode"],
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
          ["participants", participant.call_spec_key],
          "cannot be converted to a runtime participant"
        )
    end
  end

  defp speech_to_text_runtimes(plan, participants, opening_audio, options) do
    Enum.reduce_while(participants, {:ok, %{}}, fn participant, {:ok, runtimes} ->
      case speech_to_text_runtime(plan, participant, opening_audio, options) do
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

  @doc false
  def connection_speech_to_text(
        %ResolvedCallPlan{} = plan,
        %ResolvedCallPlan.Participant{kind: :human} = participant,
        options
      ) do
    speech_to_text_runtime(plan, participant, nil, options)
  end

  defp speech_to_text_runtime(plan, participant, opening_audio, options) do
    case resolve_provider(
           participant.capabilities.speech_to_text,
           plan.tenant_id,
           options,
           :speech_to_text
         ) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {provider_module, provider_config} = provider, settings} ->
        with {transport, transport_options}
             when is_atom(transport) and is_list(transport_options) <-
               Keyword.get(settings, :transport),
             media_ingress when is_list(media_ingress) <-
               Keyword.get(settings, :media_ingress),
             {:ok, usage_provider} <-
               speech_to_text_usage_provider(plan, participant, provider_module, provider_config) do
          {:ok,
           %SpeechToTextRuntime{
             call_id: plan.call_id,
             participant_id: participant.participant_id,
             activation_id: participant.activation_id,
             provider: provider,
             transport: {transport, transport_options},
             usage_provider: usage_provider,
             media_ingress:
               Keyword.put(
                 media_ingress,
                 :input_admission,
                 if(opening_audio == nil, do: :open, else: :closed)
               )
           }}
        else
          _invalid_runtime -> unsupported_speech_configuration(participant, :speech_to_text)
        end

      {:error, _reason} ->
        unsupported_speech_configuration(participant, :speech_to_text)
    end
  end

  defp speech_to_text_usage_provider(plan, participant, provider_module, provider_config) do
    selection = participant.capabilities.speech_to_text

    with true <- function_exported?(provider_module, :usage_identity, 1),
         identity when is_list(identity) <- provider_module.usage_identity(provider_config) do
      identity
      |> Keyword.put(:integration_id, CapabilitySelection.identity(selection, plan.tenant_id))
      |> ProviderContext.new()
    else
      _invalid -> {:error, :invalid_usage_identity}
    end
  end

  def opening_runtime(%ResolvedCallPlan{} = plan, options) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    opening_text_to_speech_runtime(plan, caller, options)
  end

  defp opening_text_to_speech_runtime(%ResolvedCallPlan{opening_audio: nil}, _caller, _options),
    do: {:ok, nil}

  defp opening_text_to_speech_runtime(
         %ResolvedCallPlan{
           opening_audio: %OpeningAudio{
             type: :text,
             text_to_speech: %CapabilitySelection{} = selection
           }
         } = plan,
         caller,
         options
       ) do
    text_to_speech_runtime(plan, selection, caller, options, ["opening_audio", "text_to_speech"])
  end

  defp opening_text_to_speech_runtime(
         %ResolvedCallPlan{opening_audio: %OpeningAudio{type: :file_url}},
         _caller,
         options
       ) do
    case Keyword.get(options, :opening_audio) do
      %OpeningAudioSettings{} -> {:ok, nil}
      _invalid -> unsupported(["opening_audio"], "file opening audio is not configured")
    end
  end

  defp opening_text_to_speech_runtime(_plan, _caller, _options) do
    unsupported(
      ["opening_audio", "text_to_speech"],
      "requires its own inline text-to-speech selection"
    )
  end

  @doc false
  def participant_text_to_speech(%ResolvedCallPlan{} = plan, receiver, options) do
    text_to_speech_runtime(plan, receiver, options)
  end

  defp text_to_speech_runtime(plan, receiver, options) do
    text_to_speech_runtime(
      plan,
      receiver.capabilities.text_to_speech,
      receiver,
      options,
      ["participants", receiver.call_spec_key, "capabilities", "text_to_speech"]
    )
  end

  defp text_to_speech_runtime(plan, selection, participant, options, path) do
    case resolve_provider(selection, plan.tenant_id, options, :text_to_speech) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {provider_module, provider_config} = provider, settings} ->
        with {transport, transport_options}
             when is_atom(transport) and is_list(transport_options) <-
               Keyword.get(settings, :transport),
             maximum_requests when is_integer(maximum_requests) and maximum_requests > 0 <-
               Keyword.get(settings, :maximum_requests),
             asset_cache_identity when is_map(asset_cache_identity) <-
               provider_module.asset_cache_identity(provider_config),
             {:ok, usage_provider} <-
               text_to_speech_usage_provider(plan, selection, provider_module, provider_config) do
          {:ok,
           %TextToSpeechRuntime{
             asset_cache_identity:
               Map.put(
                 asset_cache_identity,
                 "selection",
                 CapabilitySelection.identity(selection, plan.tenant_id)
               ),
             call_id: plan.call_id,
             participant_id: participant.participant_id,
             activation_id: participant.activation_id,
             provider: provider,
             transport: {transport, transport_options},
             maximum_requests: maximum_requests,
             usage_provider: usage_provider
           }}
        else
          _invalid_runtime ->
            unsupported(path, unsupported_speech_configuration_reason(:text_to_speech))
        end

      {:error, _reason} ->
        unsupported(path, unsupported_speech_configuration_reason(:text_to_speech))
    end
  end

  defp text_to_speech_usage_provider(plan, selection, provider_module, provider_config) do
    with true <- function_exported?(provider_module, :usage_identity, 1),
         identity when is_list(identity) <- provider_module.usage_identity(provider_config) do
      identity
      |> Keyword.put(:integration_id, CapabilitySelection.identity(selection, plan.tenant_id))
      |> ProviderContext.new()
    else
      _invalid -> {:error, :invalid_usage_identity}
    end
  end

  defp resolve_provider(nil, _tenant_id, _options, _kind), do: {:ok, nil}

  defp resolve_provider(
         %CapabilitySelection{} = selection,
         tenant_id,
         options,
         kind
       ) do
    with {:ok, provider} <- CapabilityCatalog.adapter(selection),
         {:ok, settings} <- provider_settings(Keyword.get(options, kind), provider),
         true <- Keyword.get(settings, :enabled) == true,
         {:ok, credential} <- CredentialSource.resolve(tenant_id, selection, options),
         {:ok, selected_options} <- CapabilityCatalog.speech_options(selection),
         {:ok, selected_options} <- authenticate_speech(selected_options, credential),
         true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :new, 1),
         {:ok, provider_config} <-
           provider.new(selected_options) do
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

  defp authenticate_speech(options, nil), do: {:ok, options}

  defp authenticate_speech(options, %Vxpipe.CallEngine.ProviderCredential{
         auth_kind: "api_key",
         payload: %{"api_key" => api_key}
       }),
       do: {:ok, Keyword.put(options, :api_key, api_key)}

  defp authenticate_speech(_options, _credential), do: {:error, :unsupported_provider_auth}

  defp current_plan(plan) do
    if plan.schema_version == Vxpipe.CallEngine.CallSpec.schema_version() do
      validate_planned_selections(plan)
    else
      unsupported(["schema_version"], "must use the current inline capability schema")
    end
  end

  defp validate_planned_selections(plan) do
    selections =
      Enum.flat_map(plan.participants, fn {ref, participant} ->
        for kind <- [:speech_to_text, :model_inference, :text_to_speech] do
          {Map.fetch!(participant.capabilities, kind), kind,
           ["participants", ref, "capabilities", Atom.to_string(kind)]}
        end
      end)

    opening =
      case plan.opening_audio do
        %{type: :text, text_to_speech: selection} ->
          [{selection, :text_to_speech, ["opening_audio", "text_to_speech"]}]

        _none ->
          []
      end

    Enum.reduce_while(selections ++ opening, :ok, fn {selection, kind, path}, :ok ->
      case valid_planned_selection(selection, kind, path) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  rescue
    _exception -> unsupported(["capabilities"], "must contain valid inline selections")
  end

  defp valid_planned_selection(nil, _kind, _path), do: :ok

  defp valid_planned_selection(%CapabilitySelection{kind: kind} = selection, kind, path) do
    case CapabilitySelection.validate(selection, path) do
      :ok -> :ok
      {:error, _reason} -> unsupported(path, "must contain a valid inline selection")
    end
  end

  defp valid_planned_selection(_selection, _kind, path),
    do: unsupported(path, "must contain a valid inline selection")

  defp unsupported_speech_configuration_reason(:speech_to_text),
    do: :unsupported_speech_to_text_configuration

  defp unsupported_speech_configuration_reason(:text_to_speech),
    do: :unsupported_text_to_speech_configuration

  defp unsupported_speech_configuration(participant, kind) do
    unsupported(
      ["participants", participant.call_spec_key, "capabilities", Atom.to_string(kind)],
      "must select a supported inline capability with available tenant credentials"
    )
  end

  defp unsupported(path, reason) do
    {:error,
     Error.new(@error_code, @error_message, details: %{"path" => path, "reason" => reason})}
  end
end
