defmodule Vxpipe.Providers.ElevenLabs.TTSSession do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider
  @behaviour Vxpipe.CallEngine.Speech.ContextTTSProvider
  alias Vxpipe.CallEngine.Speech.{ContextTTSSession, Descriptor}
  alias Vxpipe.Providers.ElevenLabs.TTS

  @impl true
  defdelegate models(), to: Vxpipe.Providers.ElevenLabs.TTS

  @impl true
  def configure(options) do
    with {:ok, public} <- TTS.public_options(options),
         true <- TTS.websocket_compatible?(public.model) do
      Descriptor.new(
        kind: :tts,
        settings: public,
        format: %{
          encoding: :linear16,
          container: :raw,
          channels: 1,
          byte_order: :little,
          signed?: true,
          sample_rate: public.sample_rate
        },
        usage_identity: %{
          provider: :elevenlabs,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity:
          :crypto.hash(:sha256, :erlang.term_to_binary({:elevenlabs_tts, 1, public}))
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: ContextTTSSession.start_link(options, __MODULE__)
  @impl true
  defdelegate speak(pid, reference, text), to: ContextTTSSession
  @impl true
  defdelegate cancel(pid, reference, playback), to: ContextTTSSession
  @impl true
  defdelegate close(pid), to: ContextTTSSession
  @impl true
  defdelegate validate_text(text), to: TTS

  @impl true
  def request_configuration(%TTS{} = config) do
    with {:ok, descriptor} <-
           configure(model: config.model, voice: config.voice, sample_rate: config.sample_rate) do
      {:ok, descriptor}
    end
  end

  def request_configuration(_config), do: {:error, :invalid_configuration}

  @impl true
  defdelegate connection_options(config), to: TTS
  @impl true
  defdelegate new_context_id(), to: TTS
  @impl true
  defdelegate open_utterance(config, context, text), to: TTS
  @impl true
  defdelegate close_utterance(config, context), to: TTS
  # This protocol already closes the flushed context when submitting an utterance.
  # Cancellation fences local output while the accepted flush drains to its final.
  @impl true
  def cancel_utterance(_config, _context), do: nil
  @impl true
  defdelegate close_socket(config), to: TTS
  @impl true
  defdelegate keepalive_payload(config, context), to: TTS
  @impl true
  defdelegate decode_frame(payload), to: TTS
  @impl true
  defdelegate validate_audio(audio), to: TTS
end
