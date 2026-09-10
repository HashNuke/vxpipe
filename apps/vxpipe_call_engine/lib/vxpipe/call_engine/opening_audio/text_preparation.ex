defmodule Vxpipe.CallEngine.OpeningAudio.TextPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.OpeningAudio.{
    Asset,
    AssetCache,
    CachedPlaybackRequest,
    Settings
  }

  alias Vxpipe.CallEngine.{Id, RoomCapabilitySupervisor, TextToSpeechRequest}

  @type result ::
          {:ok, TextToSpeechRequest.t(), nil}
          | {:ok, CachedPlaybackRequest.t(), pid()}
          | {:error, :unavailable}

  @spec start(keyword()) :: result()
  def start(options) when is_list(options) do
    text = Keyword.fetch!(options, :text)
    command = Keyword.fetch!(options, :command)
    output_sink = Keyword.fetch!(options, :output_sink)
    capability = Keyword.fetch!(options, :capability)
    cache_identity = Keyword.fetch!(options, :cache_identity)
    snapshot = Keyword.fetch!(options, :snapshot)
    participant_id = Keyword.fetch!(options, :participant_id)
    owner = Keyword.fetch!(options, :owner)
    settings = Keyword.fetch!(options, :settings)
    cache_key = AssetCache.text_key(snapshot.tenant_id, text, cache_identity)

    case fetch_cached(settings, cache_key) do
      {:ok, %Asset{} = asset} ->
        play_cached(command, output_sink, snapshot, owner, participant_id, asset)

      :miss ->
        synthesize_and_cache(
          text,
          command,
          output_sink,
          snapshot,
          capability,
          participant_id,
          cache_key,
          settings
        )
    end
  end

  defp fetch_cached(%Settings{cache: cache}, cache_key) do
    AssetCache.fetch(cache, cache_key)
  catch
    :exit, _reason -> :miss
  end

  defp play_cached(command, output_sink, snapshot, owner, participant_id, asset) do
    request = %CachedPlaybackRequest{
      tenant_id: snapshot.tenant_id,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      participant_id: participant_id,
      connection_id: command.connection_id,
      command_id: Id.generate(:command),
      correlation_id: Id.generate(:turn),
      output_sink: output_sink
    }

    case RoomCapabilitySupervisor.start_cached_opening_audio(
           snapshot.incarnation_id,
           owner,
           request,
           asset
         ) do
      {:ok, worker} -> {:ok, request, worker}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp synthesize_and_cache(
         text,
         command,
         output_sink,
         snapshot,
         capability,
         participant_id,
         cache_key,
         settings
       ) do
    command_id = Id.generate(:command)
    correlation_id = Id.generate(:turn)

    cache_options = [
      settings: settings,
      cache_key: cache_key,
      command_id: command_id,
      connection_id: command.connection_id,
      correlation_id: correlation_id,
      target_sink: output_sink
    ]

    case RoomCapabilitySupervisor.start_opening_audio_text_cache(
           snapshot.incarnation_id,
           cache_options
         ) do
      {:ok, cache_sink} ->
        request =
          text_request(
            text,
            command,
            snapshot,
            participant_id,
            command_id,
            correlation_id,
            cache_sink
          )

        submit(capability, request, snapshot.incarnation_id, cache_sink)

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  defp submit(capability, request, incarnation_id, cache_sink) do
    case TextToSpeech.synthesize(capability, request) do
      :ok ->
        {:ok, request, nil}

      {:error, _reason} ->
        _ = RoomCapabilitySupervisor.stop_capability(incarnation_id, cache_sink)
        {:error, :unavailable}
    end
  end

  defp text_request(
         text,
         %AttachConnection{} = command,
         snapshot,
         participant_id,
         command_id,
         correlation_id,
         output_sink
       ) do
    %TextToSpeechRequest{
      tenant_id: snapshot.tenant_id,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      participant_id: participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command_id,
      correlation_id: correlation_id,
      output_id: Id.generate(:event),
      text: text,
      output_sink: output_sink,
      purpose: :opening_audio
    }
  end
end
