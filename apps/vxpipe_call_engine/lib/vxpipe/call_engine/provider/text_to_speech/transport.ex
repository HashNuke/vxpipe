defmodule Vxpipe.CallEngine.Provider.TextToSpeech.Transport do
  @moduledoc false

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_control(pid(), binary()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok | {:error, term()}
end
