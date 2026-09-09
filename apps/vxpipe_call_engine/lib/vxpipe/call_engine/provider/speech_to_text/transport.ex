defmodule Vxpipe.CallEngine.Provider.SpeechToText.Transport do
  @moduledoc false

  @type connection :: map()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_audio(pid(), binary()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok | {:error, term()}
end
