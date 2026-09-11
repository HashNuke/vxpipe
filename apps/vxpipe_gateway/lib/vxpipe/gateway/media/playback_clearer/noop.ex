defmodule Vxpipe.Gateway.Media.PlaybackClearer.Noop do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Media.PlaybackClearer

  @impl true
  def clear(_options), do: :ok
end
