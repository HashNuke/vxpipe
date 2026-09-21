defmodule Vxpipe.Providers do
  @moduledoc "Manifest contract for provider-owned, optional capabilities."

  @type capability :: :credential | :credential_validation | :stt | :tts | :telephony

  @callback id() :: String.t()
  @callback capabilities() :: %{optional(capability()) => module()}
end
