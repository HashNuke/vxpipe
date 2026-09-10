defmodule Vxpipe.CallEngine.RoomAuthority.Startup do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.{DeterministicText, ModelInference}
  alias Vxpipe.CallEngine.Command.{CreateRoom, JoinParticipant}

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallVariables,
    PlanStartup,
    ResolvedCallPlan,
    RoomCapabilitySupervisor,
    TextToSpeechRuntime
  }

  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantLifecycle, State}

  @spec start_agent(CreateRoom.t() | ResolvedCallPlan.t(), keyword(), State.t()) ::
          {:ok, State.t()} | {:error, :agent_start_failed}
  def start_agent(%CreateRoom{agent: nil}, _options, %State{} = state), do: {:ok, state}

  def start_agent(%CreateRoom{} = command, _options, %State{} = state) do
    with {:ok, join_command} <-
           JoinParticipant.new(
             tenant_id: command.tenant_id,
             actor_id: command.actor_id,
             room_id: command.room_id,
             participant_id: command.agent_participant_id,
             role: :agent,
             deadline: command.deadline
           ),
         {:ok, participant, state} <- ParticipantLifecycle.start(join_command, state),
         {:ok, module, capability} <-
           start_text_capability(command.agent, participant.participant_id, state) do
      text_capability = %{
        module: module,
        monitor: Process.monitor(capability),
        participant_id: participant.participant_id,
        pid: capability
      }

      state = %{state | text_capability: text_capability}
      start_configured_text_to_speech(participant.participant_id, state)
    else
      _error -> {:error, :agent_start_failed}
    end
  end

  def start_agent(%ResolvedCallPlan{} = plan, options, %State{} = state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    startup_options = [
      owner: self(),
      call_variables: CallVariables.whereis(state.snapshot.incarnation_id),
      incarnation_id: state.snapshot.incarnation_id,
      agent_runtime: Keyword.fetch!(settings, :agent_runtime),
      agent_request_options: Keyword.get(options, :agent_request_options, []),
      speech_to_text: Keyword.fetch!(settings, :speech_to_text),
      text_to_speech: Keyword.fetch!(settings, :text_to_speech)
    ]

    with {:ok, startup} <- PlanStartup.new(plan, startup_options),
         {:ok, _caller_snapshot, state} <-
           ParticipantLifecycle.start(startup.caller_command, state),
         {:ok, receiver_snapshot, state} <-
           ParticipantLifecycle.start(
             startup.receiver_command,
             state,
             agent_activation: startup.agent_activation
           ) do
      coordinator_ref =
        AgentActivationSupervisor.child_ref(startup.receiver.activation_id, :coordinator)

      text_capability = %{
        module: AgentRuntimeCoordinator,
        monitor: nil,
        participant_id: receiver_snapshot.participant_id,
        pid: coordinator_ref
      }

      state = %{
        state
        | speech_to_text_runtime: %{
            startup.caller.participant_id => startup.speech_to_text
          },
          text_capability: text_capability
      }

      start_selected_text_to_speech(
        startup.text_to_speech,
        receiver_snapshot.participant_id,
        state
      )
    else
      _error -> {:error, :agent_start_failed}
    end
  end

  defp start_text_capability(:deterministic_text, participant_id, state) do
    case RoomCapabilitySupervisor.start_deterministic_text(
           state.snapshot.incarnation_id,
           self(),
           participant_id
         ) do
      {:ok, capability} -> {:ok, DeterministicText, capability}
      {:error, _reason} = error -> error
    end
  end

  defp start_text_capability(:model_inference, participant_id, state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    options = Keyword.fetch!(settings, :model_inference)

    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability} <-
             RoomCapabilitySupervisor.start_model_inference(
               state.snapshot.incarnation_id,
               self(),
               participant_id,
               {provider_module, provider_config},
               options
             ) do
        {:ok, ModelInference, capability}
      end
    else
      {:error, :model_inference_disabled}
    end
  end

  defp start_configured_text_to_speech(participant_id, state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    options = Keyword.fetch!(settings, :text_to_speech)

    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability} <-
             RoomCapabilitySupervisor.start_text_to_speech(
               state.snapshot.incarnation_id,
               self(),
               participant_id,
               {provider_module, provider_config},
               Keyword.fetch!(options, :transport),
               Keyword.fetch!(options, :maximum_requests)
             ) do
        text_to_speech_capability = %{
          monitor: Process.monitor(capability),
          participant_id: participant_id,
          pid: capability
        }

        {:ok, %{state | text_to_speech_capability: text_to_speech_capability}}
      else
        _error -> {:error, :text_to_speech_start_failed}
      end
    else
      {:ok, state}
    end
  end

  defp start_selected_text_to_speech(nil, _participant_id, state), do: {:ok, state}

  defp start_selected_text_to_speech(
         %TextToSpeechRuntime{} = runtime,
         participant_id,
         state
       ) do
    case RoomCapabilitySupervisor.start_text_to_speech(
           state.snapshot.incarnation_id,
           self(),
           participant_id,
           runtime.provider,
           runtime.transport,
           runtime.maximum_requests
         ) do
      {:ok, capability} ->
        text_to_speech_capability = %{
          monitor: Process.monitor(capability),
          participant_id: participant_id,
          pid: capability
        }

        {:ok, %{state | text_to_speech_capability: text_to_speech_capability}}

      {:error, _reason} ->
        {:error, :text_to_speech_start_failed}
    end
  end
end
