defmodule Vxpipe.Gateway.TestPlaybackClearer do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Media.PlaybackClearer

  @impl true
  def clear(options) do
    options
    |> Keyword.fetch!(:test_observer)
    |> send({:test_remote_playback_cleared, options})

    :ok
  end
end
