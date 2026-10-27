defmodule Vxpipe.CallEngine.TestElevenLabsRealtimeAPI do
  @moduledoc false
  def connect(config, options) when options != [] do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:realtime_credentials_started, self()})

    receive do
      :release -> connect(config, [])
    end
  end

  def connect(_config, _options),
    do: {:ok, %{url: "wss://synthetic.invalid/realtime", headers: []}}
end
