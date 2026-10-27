defmodule Vxpipe.Providers.ElevenLabs.RealtimeConnection do
  @moduledoc false
  @enforce_keys [:url, :headers]
  @derive {Inspect, only: []}
  defstruct @enforce_keys
end
