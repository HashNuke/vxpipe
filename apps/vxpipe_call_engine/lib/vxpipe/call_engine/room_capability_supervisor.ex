defmodule Vxpipe.CallEngine.RoomCapabilitySupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Capability.{
    DeterministicText,
    ModelInference,
    SpeechToText,
    TextToSpeech
  }

  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.Ingress

  alias Vxpipe.CallEngine.OpeningAudio.{
    Asset,
    CachedPlaybackRequest,
    FilePlaybackRequest,
    Player,
    Settings,
    TextCacheSink
  }

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via(incarnation_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_deterministic_text(incarnation_id, room_authority, participant_id) do
    options = [room_authority: room_authority, participant_id: participant_id]
    DynamicSupervisor.start_child(via(incarnation_id), {DeterministicText, options})
  end

  def start_model_inference(
        incarnation_id,
        room_authority,
        participant_id,
        provider,
        options
      ) do
    capability_options = [
      owner: room_authority,
      participant_id: participant_id,
      provider: provider,
      system_prompt: Keyword.fetch!(options, :system_prompt),
      maximum_context_turns: Keyword.fetch!(options, :maximum_context_turns),
      maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
      maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
      request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
      task_supervisor: Vxpipe.CallEngine.ModelInferenceTaskSupervisor
    ]

    DynamicSupervisor.start_child(
      via(incarnation_id),
      {ModelInference, capability_options}
    )
  end

  def start_text_to_speech(
        incarnation_id,
        room_authority,
        participant_id,
        provider,
        transport,
        maximum_requests,
        usage \\ nil
      ) do
    options = [
      owner: room_authority,
      participant_id: participant_id,
      provider: provider,
      transport: transport,
      maximum_requests: maximum_requests,
      task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor,
      name: text_to_speech_ref(incarnation_id, participant_id),
      usage: usage
    ]

    DynamicSupervisor.start_child(via(incarnation_id), {TextToSpeech, options})
  end

  def start_speech_to_text(
        incarnation_id,
        room_authority,
        %AttachConnection{} = command,
        provider,
        transport,
        media_ingress_options,
        usage \\ nil
      ) do
    identity = [
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id
    ]

    capability_options =
      identity ++
        [
          owner: room_authority,
          provider: provider,
          transport: transport,
          usage: usage
        ]

    case DynamicSupervisor.start_child(
           via(incarnation_id),
           {SpeechToText, capability_options}
         ) do
      {:ok, capability} ->
        case DynamicSupervisor.start_child(
               via(incarnation_id),
               {Ingress,
                identity ++
                  [capability: capability] ++ media_ingress_options}
             ) do
          {:ok, ingress} ->
            {:ok, capability, ingress}

          {:error, _reason} = error ->
            _ = DynamicSupervisor.terminate_child(via(incarnation_id), capability)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  def start_opening_audio(
        incarnation_id,
        room_authority,
        %FilePlaybackRequest{} = request,
        %Settings{} = settings
      ) do
    options = [owner: room_authority, request: request, settings: settings]
    DynamicSupervisor.start_child(via(incarnation_id), {Player, options})
  end

  def start_cached_opening_audio(
        incarnation_id,
        room_authority,
        %CachedPlaybackRequest{} = request,
        %Asset{} = asset
      ) do
    options = [owner: room_authority, request: request, asset: asset]
    DynamicSupervisor.start_child(via(incarnation_id), {Player, options})
  end

  def start_opening_audio_text_cache(incarnation_id, options) when is_list(options) do
    DynamicSupervisor.start_child(via(incarnation_id), {TextCacheSink, options})
  end

  def stop_capability(incarnation_id, capability) do
    DynamicSupervisor.terminate_child(via(incarnation_id), capability)
  end

  @spec stop_text_to_speech(String.t(), String.t()) :: :ok | {:error, term()}
  def stop_text_to_speech(incarnation_id, participant_id) do
    case GenServer.whereis(text_to_speech_ref(incarnation_id, participant_id)) do
      capability when is_pid(capability) -> stop_capability(incarnation_id, capability)
      nil -> :ok
    end
  end

  def stop_speech_to_text(incarnation_id, capability, ingress) do
    _ = DynamicSupervisor.terminate_child(via(incarnation_id), ingress)
    _ = DynamicSupervisor.terminate_child(via(incarnation_id), capability)
    :ok
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:capability_supervisor, incarnation_id}}}
  end

  defp text_to_speech_ref(incarnation_id, participant_id) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry, {:text_to_speech, incarnation_id, participant_id}}}
  end
end
