defmodule Vxpipe.Providers.MorseCodeApi.TTSRequest do
  @moduledoc false
  alias Vxpipe.Providers.ElevenLabs.PCMRequest
  alias Vxpipe.Providers.MorseCodeApi.TTS

  def run(%TTS{} = config, text, consume) when is_function(consume, 1) do
    PCMRequest.run(TTS.request_url(config), &TTS.request_options(config, text, &1), consume)
  end
end
