defmodule Vxpipe.Providers.Google.TTSSession do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider
  @behaviour Vxpipe.CallEngine.Speech.RequestTTSProvider

  alias Vxpipe.CallEngine.Speech.{Descriptor, RequestTTSSession}
  alias Vxpipe.Providers.Google.{TTS, TTSRequest}

  @impl true
  defdelegate models(), to: Vxpipe.Providers.Google.TTS

  @impl true
  def configure(options) do
    with {:ok, public} <- TTS.public_options(options) do
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
          provider: :google,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({:google_tts, 1, public}))
      )
    end
  end

  @impl true
  def start_link(options), do: RequestTTSSession.start_link(options, __MODULE__)
  @impl true
  defdelegate speak(pid, reference, text), to: RequestTTSSession
  @impl true
  defdelegate cancel(pid, reference, playback), to: RequestTTSSession
  @impl true
  defdelegate close(pid), to: RequestTTSSession

  @impl true
  defdelegate validate_text(text), to: TTS

  @impl true
  def request_configuration(%TTS{} = config) do
    with {:ok, descriptor} <- configure(model: config.model, voice: config.voice) do
      {:ok, descriptor, TTSRequest}
    end
  end

  def request_configuration(_config), do: {:error, :invalid_configuration}
end
