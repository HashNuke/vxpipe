defmodule Vxpipe.Gateway.Media.PlaybackClearer do
  @moduledoc false

  @callback clear(keyword()) :: :ok | {:error, term()}
end
