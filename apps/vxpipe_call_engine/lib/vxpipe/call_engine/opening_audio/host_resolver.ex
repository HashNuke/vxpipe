defmodule Vxpipe.CallEngine.OpeningAudio.HostResolver do
  @moduledoc false

  @callback resolve(String.t(), term()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
end
