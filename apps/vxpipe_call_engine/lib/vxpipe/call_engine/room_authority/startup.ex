defmodule Vxpipe.CallEngine.RoomAuthority.Startup do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.DeterministicText
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

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime,
    as: ParticipantTransferRuntime

  @spec start_entries(CreateRoom.t() | ResolvedCallPlan.t(), keyword(), State.t()) ::
          {:ok, State.t()} | {:error, :agent_start_failed | :entry_start_failed}
  def start_entries(%CreateRoom{agent: nil}, _options, %State{} = state), do: {:ok, state}

  def start_entries(%CreateRoom{agent: :deterministic_text} = command, _options, %State{} = state) do
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
        activation_id: nil,
        module: module,
        monitor: Process.monitor(capability),
        participant_id: participant.participant_id,
        pid: capability
      }

      {:ok, %{state | text_capability: text_capability}}
    else
      _error -> {:error, :agent_start_failed}
    end
  end

  def start_entries(%CreateRoom{}, _options, %State{}), do: {:error, :agent_start_failed}

  def start_entries(%ResolvedCallPlan{} = plan, options, %State{} = state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    startup_options = [
      owner: self(),
      call_variables: CallVariables.whereis(state.snapshot.incarnation_id),
      incarnation_id: state.snapshot.incarnation_id,
      agent_runtime:
        settings
        |> Keyword.fetch!(:agent_runtime)
        |> Keyword.put(:startup_lifecycle, state.call_lifecycle),
      agent_request_options: Keyword.get(options, :agent_request_options, []),
      credential_source: Keyword.get(options, :credential_source),
      mcp_integrations: Keyword.get(options, :mcp_integrations),
      opening_audio: Keyword.fetch!(options, :opening_audio),
      outbound_leg_connector: Keyword.get(options, :outbound_leg_connector),
      remote_mcp_connection_provider: Keyword.get(options, :remote_mcp_connection_provider),
      remote_mcp_protocol_client: Keyword.get(options, :remote_mcp_protocol_client),
      speech_to_text: Keyword.fetch!(settings, :speech_to_text),
      text_to_speech: Keyword.fetch!(settings, :text_to_speech)
    ]

    with {:ok, entries} <- PlanStartup.entries(plan),
         {:ok, _caller_snapshot, state} <-
           ParticipantLifecycle.start(entries.caller_command, state),
         {:ok, state} <- start_human_receiver(entries, state) do
      runtime = %ParticipantTransferRuntime{plan: plan, startup_options: startup_options}
      incarnation = state.snapshot.incarnation_id

      task =
        Task.Supervisor.async(Vxpipe.CallEngine.ReadinessTaskSupervisor, fn ->
          {:startup_prepared, prepare_entries(plan, startup_options, incarnation)}
        end)

      {:ok,
       %{
         state
         | participant_transfer_runtime: runtime,
           startup: %{
             task: task,
             opening_task: prepare_opening(plan, startup_options, incarnation),
             status: :preparing,
             waits: %{},
             readiness: nil,
             release_task: nil,
             ready_graph: nil,
             resources_ready?: false,
             deadline_ms: Vxpipe.CallEngine.CallLifecycle.readiness_deadline(state.call_lifecycle)
           }
       }}
    else
      _error -> {:error, :entry_start_failed}
    end
  end

  defp start_human_receiver(%{receiver: %{kind: :agent}}, state), do: {:ok, state}

  defp start_human_receiver(entries, state) do
    with {:ok, _receiver, state} <- ParticipantLifecycle.start(entries.receiver_command, state),
         do: {:ok, %{state | text_capability_required?: false}}
  end

  defp prepare_entries(plan, options, incarnation) do
    owner = Keyword.fetch!(options, :owner)

    with {:ok, startup} <- PlanStartup.new(plan, options),
         {:ok, participant} <- prepare_receiver(startup, incarnation),
         {:ok, voice} <-
           prepare_text_to_speech(
             startup.text_to_speech,
             startup.receiver.participant_id,
             incarnation,
             owner
           ) do
      {:ok,
       %{
         configuration: startup,
         participant: participant,
         voice: voice
       }}
    end
  rescue
    _exception -> {:error, :entry_start_failed}
  catch
    :exit, _reason -> {:error, :entry_start_failed}
  end

  defp prepare_opening(%{opening_audio: %{type: :text}} = plan, options, incarnation) do
    owner = Keyword.fetch!(options, :owner)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    Task.Supervisor.async(Vxpipe.CallEngine.ReadinessTaskSupervisor, fn ->
      result =
        with {:ok, runtime} <- PlanStartup.opening_runtime(plan, options),
             do: prepare_text_to_speech(runtime, caller.participant_id, incarnation, owner)

      {:opening_prepared, result}
    end)
  end

  defp prepare_opening(_plan, _options, _incarnation), do: nil

  defp prepare_receiver(%{receiver: %{kind: :human}}, _incarnation), do: {:ok, nil}

  defp prepare_receiver(startup, incarnation) do
    command = %{startup.receiver_command | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

    ParticipantLifecycle.prepare(
      command,
      incarnation,
      entry_activation_options(startup.agent_activation)
    )
  end

  def install(prepared, state) do
    with {:ok, state} <- commit_receiver(prepared.participant, state) do
      startup = prepared.configuration

      state = %{
        state
        | speech_to_text_runtime: startup.speech_to_text_runtimes,
          text_to_speech_capability: activate_text_to_speech(prepared.voice),
          text_to_speech_runtime: startup.text_to_speech,
          startup: %{state.startup | task: nil, status: :prepared}
      }

      bind_entry_receiver(startup, state)
    end
  end

  defp commit_receiver(nil, state), do: {:ok, state}

  defp commit_receiver(participant, state) do
    with {:ok, _snapshot, state} <- ParticipantLifecycle.commit(participant, state),
         do: {:ok, state}
  end

  defp bind_entry_receiver(%{receiver: %{kind: :human}}, state), do: {:ok, state}

  defp bind_entry_receiver(startup, state) do
    receiver = startup.receiver

    capability = %{
      activation_id: receiver.activation_id,
      module: AgentRuntimeCoordinator,
      monitor: nil,
      participant_id: receiver.participant_id,
      pid: AgentActivationSupervisor.child_ref(receiver.activation_id, :coordinator)
    }

    {:ok, %{state | text_capability: capability}}
  end

  defp entry_activation_options(nil), do: []
  defp entry_activation_options(options) when is_list(options), do: [agent_activation: options]

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

  @spec prepare_text_to_speech(nil | TextToSpeechRuntime.t(), String.t(), State.t()) ::
          {:ok, nil | map()} | {:error, :text_to_speech_start_failed}
  def prepare_text_to_speech(nil, _participant_id, %State{}), do: {:ok, nil}

  def prepare_text_to_speech(
        %TextToSpeechRuntime{} = runtime,
        participant_id,
        %State{} = state
      ) do
    prepare_text_to_speech(
      runtime,
      participant_id,
      state.snapshot.incarnation_id,
      self()
    )
  end

  @spec prepare_text_to_speech(
          nil | TextToSpeechRuntime.t(),
          String.t(),
          String.t(),
          pid()
        ) :: {:ok, nil | map()} | {:error, :text_to_speech_start_failed}
  def prepare_text_to_speech(nil, _participant_id, incarnation_id, owner)
      when is_binary(incarnation_id) and is_pid(owner),
      do: {:ok, nil}

  def prepare_text_to_speech(
        %TextToSpeechRuntime{} = runtime,
        participant_id,
        incarnation_id,
        owner
      )
      when is_binary(incarnation_id) and is_pid(owner) do
    case RoomCapabilitySupervisor.start_text_to_speech(
           incarnation_id,
           owner,
           participant_id,
           runtime.provider,
           runtime.provider_private,
           runtime.maximum_requests,
           text_to_speech_usage(runtime, participant_id)
         ) do
      {:ok, capability} ->
        text_to_speech_capability = %{
          activation_id: usage_activation(runtime, participant_id),
          asset_cache_identity: runtime.asset_cache_identity,
          monitor: nil,
          participant_id: participant_id,
          pid: capability
        }

        {:ok, text_to_speech_capability}

      {:error, _reason} ->
        {:error, :text_to_speech_start_failed}
    end
  end

  @spec discard_text_to_speech(nil | map(), State.t()) :: :ok | {:error, term()}
  def discard_text_to_speech(nil, %State{}), do: :ok

  def discard_text_to_speech(capability, %State{} = state) when is_map(capability) do
    if is_reference(capability.monitor), do: Process.demonitor(capability.monitor, [:flush])

    RoomCapabilitySupervisor.stop_capability(
      state.snapshot.incarnation_id,
      capability.pid
    )
  end

  @spec activate_text_to_speech(nil | map()) :: nil | map()
  def activate_text_to_speech(nil), do: nil

  def activate_text_to_speech(capability) when is_map(capability) do
    %{capability | monitor: Process.monitor(capability.pid)}
  end

  defp text_to_speech_usage(runtime, participant_id) do
    [
      call_id: runtime.call_id,
      activation_id: usage_activation(runtime, participant_id),
      provider: runtime.usage_provider
    ]
  end

  defp usage_activation(runtime, participant_id) do
    if runtime.participant_id == participant_id, do: runtime.activation_id, else: nil
  end
end
