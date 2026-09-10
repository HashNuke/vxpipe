defmodule Vxpipe.CallEngine.TestOpeningAudioFetcher do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.OpeningAudio.Fetcher

  @impl true
  def fetch(url, limits, options) do
    send(Keyword.fetch!(options, :observer), {:test_opening_audio_fetch, url, limits})
    Keyword.fetch!(options, :response)
  end
end
