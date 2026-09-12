defmodule Vxpipe.CallEngine do
  @moduledoc """
  Owns Vxpipe's protocol-neutral call lifecycle and processing runtime.
  """

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    CreateRoom,
    JoinParticipant,
    ParticipantTransferControl,
    SendText
  }

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler}
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.DefinitionValidation
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress, NormalizedFrame}
  alias Vxpipe.CallEngine.LiveInspection.Buffer, as: LiveInspectionBuffer
  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationCatalog}
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.RoomSupervisor
  alias Vxpipe.CallEngine.RoomAudioHandle
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  @spec compile_definition(CallDefinition.t(), CallInvocation.t(), map(), keyword()) ::
          {:ok, ResolvedCallPlan.t()} | {:error, Error.t()}
  def compile_definition(definition, invocation, registries, options \\ [])

  def compile_definition(
        %CallDefinition{} = definition,
        %CallInvocation{} = invocation,
        registries,
        options
      )
      when is_map(registries) and is_list(options) do
    {catalog_store, compiler_options} =
      Keyword.pop(options, :mcp_catalog_store, CatalogStore)

    with {:ok, integrations} <- catalog_snapshot(catalog_store) do
      registries = Map.put(registries, :mcp_integrations, integrations)
      DefinitionCompiler.compile(definition, invocation, registries, compiler_options)
    end
  end

  @spec start_call(ResolvedCallPlan.t(), keyword()) ::
          {:ok, Vxpipe.CallEngine.Room.Snapshot.t()} | {:error, Error.t()}
  def start_call(%ResolvedCallPlan{} = plan, options \\ []) when is_list(options) do
    with {:ok, runtime_options} <- runtime_options(plan, options) do
      RoomSupervisor.start_call(plan, runtime_options)
    end
  end

  @spec create_room(CreateRoom.t()) ::
          {:ok, Vxpipe.CallEngine.Room.Snapshot.t()} | {:error, Error.t()}
  def create_room(%CreateRoom{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.create_room(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The create-room command deadline has elapsed."
       )}
    end
  end

  @spec participant_snapshot(String.t(), String.t(), String.t()) ::
          {:ok, Vxpipe.CallEngine.Participant.Snapshot.t()} | {:error, Error.t()}
  def participant_snapshot(tenant_id, room_id, participant_id)
      when is_binary(tenant_id) and is_binary(room_id) and is_binary(participant_id) do
    RoomSupervisor.participant_snapshot(tenant_id, room_id, participant_id)
  end

  @spec inspect_live_call(String.t(), String.t()) ::
          {:ok, Vxpipe.CallEngine.LiveInspection.Snapshot.t()} | {:error, :call_not_live}
  def inspect_live_call(tenant_id, call_id) when is_binary(tenant_id) and is_binary(call_id) do
    LiveInspectionBuffer.snapshot(tenant_id, call_id)
  end

  @doc "Records trusted, provider-neutral carrier usage without blocking the live room."
  @spec record_telephony_usage([Vxpipe.CallEngine.Usage.Observation.t()]) ::
          :ok | {:error, :invalid_telephony_usage | :room_not_found}
  def record_telephony_usage(observations) when is_list(observations) do
    RoomSupervisor.record_telephony_usage(observations)
  end

  @spec join_participant(JoinParticipant.t()) ::
          {:ok, Vxpipe.CallEngine.Participant.Snapshot.t()} | {:error, Error.t()}
  def join_participant(%JoinParticipant{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.join_participant(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The join-participant command deadline has elapsed."
       )}
    end
  end

  @spec attach_connection(AttachConnection.t()) ::
          {:ok, ConnectionAttachment.t()} | {:error, Error.t()}
  def attach_connection(%AttachConnection{} = command, output_sink \\ nil) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

      case RoomSupervisor.attach_connection(
             command,
             Keyword.fetch!(settings, :speech_to_text),
             output_sink
           ) do
        {:ok, _room_authority, room_monitor, media_ingress, admission, room_audio_input_mode,
         room_audio_output_mode, transfer_attempt_id} ->
          case RoomAudioHandle.resolve(command.incarnation_id) do
            {:ok, room_audio} ->
              {:ok,
               %ConnectionAttachment{
                 admission: admission,
                 room_monitor: room_monitor,
                 media_ingress: media_ingress,
                 room_audio: room_audio,
                 room_audio_input_mode: room_audio_input_mode(room_audio, room_audio_input_mode),
                 room_audio_output_mode:
                   room_audio_output_mode(room_audio, room_audio_output_mode),
                 transfer_attempt_id: transfer_attempt_id
               }}

            {:error, :unavailable} ->
              {:error,
               Error.new(
                 :room_audio_unavailable,
                 "The room audio pipeline is unavailable.",
                 retryable: true
               )}
          end

        {:error, %Error{} = error} ->
          {:error, error}
      end
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The attach-connection command deadline has elapsed."
       )}
    end
  end

  @spec participant_transfer_control(ParticipantTransferControl.t()) ::
          :ok | {:error, Error.t()}
  def participant_transfer_control(%ParticipantTransferControl{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.participant_transfer_control(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The participant-transfer-control command deadline has elapsed."
       )}
    end
  end

  @spec push_audio(ConnectionAttachment.t(), AudioFrame.t()) ::
          :ok
          | {:error,
             :media_overloaded
             | :queue_full
             | :speech_to_text_unavailable
             | :stale_frame
             | :unavailable
             | :wrong_connection
             | :wrong_track}
  def push_audio(%ConnectionAttachment{media_ingress: nil}, %AudioFrame{}) do
    {:error, :speech_to_text_unavailable}
  end

  def push_audio(%ConnectionAttachment{media_ingress: media_ingress}, %AudioFrame{} = frame) do
    Ingress.push(media_ingress, frame)
  end

  @spec room_audio_configuration(ConnectionAttachment.t()) :: {:ok, map()} | :disabled
  def room_audio_configuration(%ConnectionAttachment{room_audio_input_mode: :disabled}),
    do: :disabled

  def room_audio_configuration(%ConnectionAttachment{
        room_audio_input_mode: :enabled,
        room_audio: %RoomAudioHandle{} = handle
      }) do
    {:ok, handle.configuration}
  end

  @spec register_room_audio_enforcer(ConnectionAttachment.t(), pid()) ::
          {:ok, Vxpipe.CallEngine.MediaPolicy.Snapshot.t()} | {:error, :disabled | term()}
  def register_room_audio_enforcer(%ConnectionAttachment{room_audio: nil}, enforcer)
      when is_pid(enforcer),
      do: {:error, :disabled}

  def register_room_audio_enforcer(
        %ConnectionAttachment{room_audio: %RoomAudioHandle{} = handle},
        enforcer
      )
      when is_pid(enforcer) do
    RoomAudioHandle.register_enforcer(handle, enforcer)
  end

  @spec push_room_audio(ConnectionAttachment.t(), NormalizedFrame.t()) ::
          :ok | {:error, :disabled | term()}
  def push_room_audio(
        %ConnectionAttachment{room_audio_input_mode: :disabled},
        %NormalizedFrame{}
      ),
      do: {:error, :disabled}

  def push_room_audio(
        %ConnectionAttachment{
          room_audio_input_mode: :enabled,
          room_audio: %RoomAudioHandle{} = handle
        },
        %NormalizedFrame{} = frame
      ) do
    RoomAudioHandle.push(handle, frame)
  end

  @spec room_audio_output_configuration(ConnectionAttachment.t()) ::
          {:ok, %{mode: :full_mix | :mix_minus}} | :disabled
  def room_audio_output_configuration(%ConnectionAttachment{room_audio_output_mode: :disabled}),
    do: :disabled

  def room_audio_output_configuration(%ConnectionAttachment{room_audio_output_mode: :mix_minus}),
    do: {:ok, %{mode: :mix_minus}}

  def room_audio_output_configuration(%ConnectionAttachment{room_audio_output_mode: :full_mix}),
    do: {:ok, %{mode: :full_mix}}

  @spec subscribe_room_audio(ConnectionAttachment.t(), keyword()) ::
          {:ok, Vxpipe.CallEngine.RoomMixer.Subscription.t()} | {:error, term()}
  def subscribe_room_audio(
        %ConnectionAttachment{
          room_audio_output_mode: mode,
          room_audio: %RoomAudioHandle{} = handle
        },
        options
      )
      when mode in [:full_mix, :mix_minus] and is_list(options) do
    RoomAudioHandle.subscribe(handle, Keyword.put(options, :mode, mode))
  end

  def subscribe_room_audio(%ConnectionAttachment{}, options) when is_list(options),
    do: {:error, :disabled}

  @spec take_room_audio(Subscription.t(), pos_integer()) ::
          {:ok, [Vxpipe.CallEngine.Media.MixedFrame.t()]} | {:error, term()}
  def take_room_audio(%Subscription{} = subscription, maximum_frames)
      when is_integer(maximum_frames) and maximum_frames > 0 do
    Subscription.take(subscription, maximum_frames)
  end

  @spec send_text(SendText.t()) :: :ok | {:error, Error.t()}
  def send_text(%SendText{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.send_text(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The send-text command deadline has elapsed."
       )}
    end
  end

  defp room_audio_input_mode(%RoomAudioHandle{}, :enabled), do: :enabled
  defp room_audio_input_mode(_room_audio, _mode), do: :disabled

  defp room_audio_output_mode(%RoomAudioHandle{}, :full_mix), do: :full_mix
  defp room_audio_output_mode(%RoomAudioHandle{}, :mix_minus), do: :mix_minus
  defp room_audio_output_mode(_room_audio, _mode), do: :disabled

  defp catalog_snapshot(catalog_store) do
    case CatalogStore.snapshot(catalog_store) do
      {:ok, %IntegrationCatalog{}} = result -> result
      _unavailable -> unavailable_catalog()
    end
  catch
    :exit, _reason -> unavailable_catalog()
  end

  defp runtime_options(plan, options) do
    if remote_tools?(plan) do
      {catalog_store, options} = Keyword.pop(options, :mcp_catalog_store, CatalogStore)

      with {:ok, integrations} <- catalog_snapshot(catalog_store) do
        {:ok, Keyword.put(options, :mcp_integrations, integrations)}
      end
    else
      {:ok, Keyword.delete(options, :mcp_integrations)}
    end
  end

  defp remote_tools?(plan) do
    Enum.any?(plan.participants, fn {_key, participant} ->
      Enum.any?(participant.tools, fn
        {_name, %ResolvedCallPlan.ToolBinding{type: :mcp}} -> true
        _binding -> false
      end)
    end)
  end

  defp unavailable_catalog do
    DefinitionValidation.invalid(
      :call_definition_resolution_failed,
      "The call definition could not be resolved.",
      ["registries", "mcp_integrations"],
      "is unavailable"
    )
  end
end
