defmodule Vxpipe.CallEngine.TestOpeningAudioFetcher do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.OpeningAudio.Fetcher

  @impl true
  def fetch(url, limits, options) do
    send(Keyword.fetch!(options, :observer), {:test_opening_audio_fetch, url, limits})

    case Keyword.fetch!(options, :response) do
      response when is_function(response, 0) -> response.()
      response -> response
    end
  end
end
