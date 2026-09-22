defmodule Vxpipe.CallEngine.RoomCapabilitySupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Capability.{
    DeterministicText,
    ModelInference
  }

  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree, as: SpeechToSpeechTree
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree, as: TextToSpeechTree
  alias Vxpipe.CallEngine.Speech.PrivateInit

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
        provider_private,
        maximum_requests,
        usage \\ nil
      ) do
    with {:ok, private_init} <- PrivateInit.open(provider_private, 5_000) do
      options = [
        owner: room_authority,
        participant_id: participant_id,
        provider: provider,
        provider_private: private_init,
        maximum_requests: maximum_requests,
        name: text_to_speech_ref(incarnation_id, participant_id),
        usage: usage
      ]

      result =
        try do
          DynamicSupervisor.start_child(via(incarnation_id), {TextToSpeechTree, options})
        after
          PrivateInit.close(private_init)
        end

      case result do
        {:ok, tree} -> {:ok, TextToSpeechTree.capability(tree)}
        {:error, _reason} = error -> error
      end
    end
  end

  def whereis_text_to_speech(incarnation_id, participant_id),
    do: GenServer.whereis(text_to_speech_ref(incarnation_id, participant_id))

  def start_speech_to_speech(incarnation_id, options) when is_list(options) do
    owner = Keyword.fetch!(options, :owner)
    agent_id = Keyword.fetch!(options, :agent_id)
    provider = Keyword.fetch!(options, :provider)
    provider_private = Keyword.get(options, :provider_private, [])
    output_private = Keyword.get(options, :output_stt_private, [])

    with {:ok, private_init} <- PrivateInit.open(provider_private, 5_000),
         {:ok, output_init} <- PrivateInit.open(output_private, 5_000) do
      tree_options =
        [
          owner: owner,
          agent_id: agent_id,
          provider: provider,
          provider_private: private_init,
          output_stt_private: output_init,
          name: speech_to_speech_ref(incarnation_id, agent_id)
        ] ++
          Keyword.take(options, [
            :human_id,
            :input_required?,
            :sink,
            :policy,
            :policy_revision,
            :caller_source,
            :frame_identity,
            :usage_context,
            :output_generation,
            :output_stt
          ])

      result =
        try do
          DynamicSupervisor.start_child(via(incarnation_id), {SpeechToSpeechTree, tree_options})
        after
          PrivateInit.close(private_init)
          PrivateInit.close(output_init)
        end

      case result do
        {:ok, tree} -> {:ok, SpeechToSpeechTree.capability(tree)}
        {:error, _reason} = error -> error
      end
    end
  end

  def whereis_speech_to_speech(incarnation_id, agent_id),
    do: GenServer.whereis(speech_to_speech_ref(incarnation_id, agent_id))

  def stop_speech_to_speech(incarnation_id, agent_id) do
    case GenServer.whereis(speech_to_speech_ref(incarnation_id, agent_id)) do
      capability when is_pid(capability) -> stop_capability(incarnation_id, capability)
      nil -> :ok
    end
  end

  def start_speech_to_text(
        incarnation_id,
        room_authority,
        %AttachConnection{} = command,
        provider,
        media_ingress_options,
        usage \\ nil,
        initialization_options \\ []
      ) do
    identity = [
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id
    ]

    private = Keyword.get(initialization_options, :provider_private, [])
    expires_in = max(DateTime.diff(command.deadline, DateTime.utc_now(), :millisecond), 1)

    with {:ok, private_init} <- PrivateInit.open(private, expires_in) do
      capability_options =
        identity ++
          [
            owner: room_authority,
            provider: provider,
            provider_private: private_init,
            usage: usage
          ] ++ Keyword.take(initialization_options, [:initial_policy, :preparation])

      tree_options = [
        owner: room_authority,
        incarnation_id: incarnation_id,
        connection_id: command.connection_id,
        capability_options: capability_options,
        ingress_options: identity ++ media_ingress_options
      ]

      result =
        try do
          DynamicSupervisor.start_child(via(incarnation_id), {ConnectionTree, tree_options})
        after
          PrivateInit.close(private_init)
        end

      case result do
        {:ok, tree} ->
          ConnectionTree.children(tree)

        {:error, _reason} = error ->
          error
      end
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

  def start_opening_audio_gate(incarnation_id, options) when is_list(options) do
    DynamicSupervisor.start_child(
      via(incarnation_id),
      {Vxpipe.CallEngine.OpeningAudio.PlaybackGate, options}
    )
  end

  def start_wait_audio(incarnation_id, options) when is_list(options) do
    options = Keyword.put(options, :incarnation_id, incarnation_id)

    DynamicSupervisor.start_child(
      via(incarnation_id),
      {Vxpipe.CallEngine.WaitSounds.Player, options}
    )
  end

  def start_readiness(incarnation_id, options) when is_list(options) do
    options = Keyword.put(options, :incarnation_id, incarnation_id)

    DynamicSupervisor.start_child(
      via(incarnation_id),
      {Vxpipe.CallEngine.Readiness.Collector, options}
    )
  end

  def stop_capability(incarnation_id, capability) do
    child =
      TextToSpeechTree.parent(capability) || SpeechToSpeechTree.parent(capability) || capability

    DynamicSupervisor.terminate_child(via(incarnation_id), child)
  end

  @spec stop_text_to_speech(String.t(), String.t()) :: :ok | {:error, term()}
  def stop_text_to_speech(incarnation_id, participant_id) do
    case GenServer.whereis(text_to_speech_ref(incarnation_id, participant_id)) do
      capability when is_pid(capability) -> stop_capability(incarnation_id, capability)
      nil -> :ok
    end
  end

  def stop_speech_to_text(incarnation_id, capability, ingress) do
    case ConnectionTree.parent(capability) do
      tree when is_pid(tree) ->
        _ = DynamicSupervisor.terminate_child(via(incarnation_id), tree)

      nil ->
        _ = DynamicSupervisor.terminate_child(via(incarnation_id), ingress)
        _ = DynamicSupervisor.terminate_child(via(incarnation_id), capability)
    end

    :ok
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:capability_supervisor, incarnation_id}}}
  end

  defp text_to_speech_ref(incarnation_id, participant_id) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry, {:text_to_speech, incarnation_id, participant_id}}}
  end

  defp speech_to_speech_ref(incarnation_id, agent_id) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry, {:speech_to_speech, incarnation_id, agent_id}}}
  end
end
