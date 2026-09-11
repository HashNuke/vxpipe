defmodule Vxpipe.CallEngine.RoomSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy
  alias Vxpipe.CallEngine.Archive.Handoff
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.CallEngine.OpeningAudio.Settings, as: OpeningAudioSettings

  alias Vxpipe.CallEngine.{
    CallLifecycle,
    Error,
    Id,
    ParticipantAuthority,
    PlanStartup,
    RoomAuthority,
    RoomCapabilitySupervisor,
    RoomIncarnationSupervisor,
    SpeechToTextRuntime
  }

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def create_room(%CreateRoom{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [] -> start_room(command)
      [_room] -> {:error, room_already_exists(command.room_id)}
    end
  end

  def start_call(%ResolvedCallPlan{} = plan, options) when is_list(options) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
      [] ->
        with {:ok, opening_audio} <- opening_audio_settings(),
             runtime_options = Keyword.put(options, :opening_audio, opening_audio),
             :ok <- PlanStartup.validate(plan, plan_startup_options(runtime_options)) do
          archive = prepare_archive(options)
          start_planned_room(plan, runtime_options, archive)
        end

      [_room] ->
        {:error, room_already_exists(plan.room_id)}
    end
  end

  def join_participant(%JoinParticipant{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [{room_authority, _value}] -> RoomAuthority.join_participant(room_authority, command)
      [] -> {:error, room_not_found(command.room_id)}
    end
  end

  def participant_snapshot(tenant_id, room_id, participant_id) do
    key = {:participant, tenant_id, room_id, participant_id}

    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key) do
      [{participant_authority, _value}] ->
        {:ok, ParticipantAuthority.snapshot(participant_authority)}

      [] ->
        {:error,
         Error.new(
           :participant_not_found,
           "The participant does not exist.",
           details: %{"participant_id" => participant_id}
         )}
    end
  catch
    :exit, _reason ->
      {:error,
       Error.new(
         :participant_not_found,
         "The participant does not exist.",
         details: %{"participant_id" => participant_id}
       )}
  end

  def attach_connection(%AttachConnection{} = command, speech_to_text_options, output_sink) do
    case lookup_room(command.tenant_id, command.room_id) do
      {:ok, room_authority} ->
        case RoomAuthority.attach_connection(room_authority, command, self(), output_sink) do
          {:ok, role, selected_runtime, output_mode} ->
            start_connection_speech_to_text(
              room_authority,
              command,
              role,
              selected_runtime,
              output_mode,
              speech_to_text_options
            )

          {:error, %Error{} = error} ->
            {:error, error}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp start_connection_speech_to_text(
         room_authority,
         command,
         :human,
         :application,
         output_mode,
         options
       ) do
    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability, ingress} <-
             RoomCapabilitySupervisor.start_speech_to_text(
               command.incarnation_id,
               room_authority,
               command,
               {provider_module, provider_config},
               Keyword.fetch!(options, :transport),
               Keyword.fetch!(options, :media_ingress)
             ) do
        bind_connection_speech_to_text(
          room_authority,
          command,
          capability,
          ingress,
          output_mode
        )
      else
        _error -> attachment_speech_to_text_failed(room_authority, command)
      end
    else
      {:ok, room_authority, nil, output_mode}
    end
  end

  defp start_connection_speech_to_text(
         room_authority,
         command,
         :human,
         %SpeechToTextRuntime{} = runtime,
         output_mode,
         _application_options
       ) do
    with {:ok, capability, ingress} <-
           RoomCapabilitySupervisor.start_speech_to_text(
             command.incarnation_id,
             room_authority,
             command,
             runtime.provider,
             runtime.transport,
             runtime.media_ingress
           ) do
      bind_connection_speech_to_text(
        room_authority,
        command,
        capability,
        ingress,
        output_mode
      )
    else
      _error -> attachment_speech_to_text_failed(room_authority, command)
    end
  end

  defp start_connection_speech_to_text(
         room_authority,
         _command,
         _role,
         _selected_runtime,
         output_mode,
         _application_options
       ) do
    {:ok, room_authority, nil, output_mode}
  end

  defp bind_connection_speech_to_text(
         room_authority,
         command,
         capability,
         ingress,
         output_mode
       ) do
    case RoomAuthority.bind_speech_to_text(
           room_authority,
           command,
           self(),
           capability,
           ingress
         ) do
      :ok ->
        {:ok, room_authority, ingress, output_mode}

      {:error, _reason} ->
        :ok =
          RoomCapabilitySupervisor.stop_speech_to_text(
            command.incarnation_id,
            capability,
            ingress
          )

        attachment_speech_to_text_failed(room_authority, command)
    end
  end

  defp attachment_speech_to_text_failed(room_authority, command) do
    case CallLifecycle.startup_failed(command.incarnation_id, :speech_to_text_unavailable) do
      :ok -> :ok
      {:ignored, status} when status in [:expired, :failed] -> :ok
      {:ignored, :ready} -> RoomAuthority.detach_connection(room_authority, command, self())
      {:error, :unavailable} -> RoomAuthority.detach_connection(room_authority, command, self())
    end

    {:error,
     Error.new(
       :speech_to_text_unavailable,
       "The speech-to-text capability could not be started.",
       retryable: true
     )}
  end

  def send_text(%SendText{} = command) do
    case lookup_room(command.tenant_id, command.room_id) do
      {:ok, room_authority} -> RoomAuthority.send_text(room_authority, command)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp start_room(command) do
    incarnation_id = Id.generate(:room_incarnation)
    options = [command: command, incarnation_id: incarnation_id]

    case DynamicSupervisor.start_child(__MODULE__, {RoomIncarnationSupervisor, options}) do
      {:ok, _supervisor} ->
        {:ok, RoomAuthority.snapshot(command.tenant_id, command.room_id)}

      {:error, {:shutdown, {:failed_to_start_child, RoomAuthority, {:already_started, _pid}}}} ->
        {:error, room_already_exists(command.room_id)}

      {:error, _reason} ->
        {:error,
         Error.new(
           :room_start_failed,
           "The room incarnation could not be started.",
           retryable: true
         )}
    end
  end

  defp start_planned_room(plan, runtime_options, archive) do
    incarnation_id = Id.generate(:room_incarnation)

    options = [
      plan: plan,
      incarnation_id: incarnation_id,
      start_command_id: Id.generate(:command),
      agent_request_options: Keyword.get(runtime_options, :agent_request_options, []),
      archive_handoff: archive.handoff,
      archive_source_policy: archive.source_policy,
      call_lifecycle: call_lifecycle_options(runtime_options),
      live_inspection: live_inspection_options(),
      room_mixer: room_mixer_options(),
      transcript_router: transcript_router_options(),
      opening_audio: Keyword.fetch!(runtime_options, :opening_audio),
      mcp_integrations: Keyword.get(runtime_options, :mcp_integrations),
      remote_mcp_connection_provider:
        Keyword.get(runtime_options, :remote_mcp_connection_provider),
      remote_mcp_protocol_client: Keyword.get(runtime_options, :remote_mcp_protocol_client),
      media_policy_ceiling:
        Keyword.get(runtime_options, :media_policy_ceiling, MediaPolicy.inherit())
    ]

    case DynamicSupervisor.start_child(__MODULE__, {RoomIncarnationSupervisor, options}) do
      {:ok, supervisor} ->
        source_started(archive.handoff, supervisor)
        {:ok, RoomAuthority.snapshot(plan.tenant_id, plan.room_id)}

      {:error, {:shutdown, {:failed_to_start_child, RoomAuthority, {:already_started, _pid}}}} ->
        source_stopped(archive.handoff, :room_already_exists)
        {:error, room_already_exists(plan.room_id)}

      {:error, _reason} ->
        source_stopped(archive.handoff, :room_start_failed)

        {:error,
         Error.new(
           :room_start_failed,
           "The room incarnation could not be started.",
           retryable: true
         )}
    end
  end

  defp prepare_archive(runtime_options) do
    source_policy = archive_source_policy(runtime_options)

    case Keyword.get(runtime_options, :archive_handoff) do
      %Handoff{} = handoff ->
        %{handoff: handoff, source_policy: source_policy}

      nil ->
        %{handoff: open_archive(runtime_options), source_policy: source_policy}
    end
  end

  defp open_archive(runtime_options) do
    archive = Keyword.get(runtime_options, :archive, enabled: false)

    if Keyword.get(archive, :enabled, false) do
      archive
      |> Keyword.drop([:enabled, :source_policy])
      |> ArchiveSupervisor.open()
      |> case do
        {:ok, handoff} -> handoff
        {:error, _reason} -> nil
      end
    end
  end

  defp archive_source_policy(runtime_options) do
    runtime_options
    |> Keyword.get(:archive, [])
    |> Keyword.get(:source_policy, %{"revision" => 0})
  end

  defp source_started(nil, _source), do: :ok
  defp source_started(handoff, source), do: Handoff.source_started(handoff, source)

  defp source_stopped(nil, _reason), do: :ok
  defp source_stopped(handoff, reason), do: Handoff.source_stopped(handoff, reason)

  defp plan_startup_options(runtime_options) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    [
      owner: self(),
      agent_runtime: Keyword.fetch!(settings, :agent_runtime),
      agent_request_options: Keyword.get(runtime_options, :agent_request_options, []),
      mcp_integrations: Keyword.get(runtime_options, :mcp_integrations),
      opening_audio: Keyword.fetch!(runtime_options, :opening_audio),
      speech_to_text: Keyword.fetch!(settings, :speech_to_text),
      text_to_speech: Keyword.fetch!(settings, :text_to_speech)
    ]
  end

  defp opening_audio_settings do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    case settings |> Keyword.fetch!(:opening_audio) |> OpeningAudioSettings.new() do
      {:ok, opening_audio} ->
        {:ok, opening_audio}

      {:error, _reason} ->
        {:error,
         Error.new(
           :unsupported_call_plan,
           "The resolved call plan is not supported by this runtime.",
           details: %{
             "path" => ["opening_audio"],
             "reason" => "runtime configuration is invalid"
           }
         )}
    end
  end

  defp call_lifecycle_options(runtime_options) do
    defaults =
      :vxpipe_call_engine
      |> Application.fetch_env!(Vxpipe.CallEngine.Application)
      |> Keyword.fetch!(:call_lifecycle)

    Keyword.merge(defaults, Keyword.get(runtime_options, :call_lifecycle, []))
  end

  defp live_inspection_options do
    :vxpipe_call_engine
    |> Application.fetch_env!(Vxpipe.CallEngine.Application)
    |> Keyword.fetch!(:live_inspection)
  end

  defp room_mixer_options do
    :vxpipe_call_engine
    |> Application.fetch_env!(Vxpipe.CallEngine.Application)
    |> Keyword.fetch!(:room_mixer)
  end

  defp transcript_router_options do
    :vxpipe_call_engine
    |> Application.fetch_env!(Vxpipe.CallEngine.Application)
    |> Keyword.fetch!(:transcript_router)
  end

  defp lookup_room(tenant_id, room_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}) do
      [{room_authority, _value}] -> {:ok, room_authority}
      [] -> {:error, room_not_found(room_id)}
    end
  end

  defp room_already_exists(room_id) do
    Error.new(
      :room_already_exists,
      "The room already exists.",
      details: %{"room_id" => room_id}
    )
  end

  defp room_not_found(room_id) do
    Error.new(
      :room_not_found,
      "The room does not exist.",
      details: %{"room_id" => room_id}
    )
  end
end
