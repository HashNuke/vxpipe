defmodule Vxpipe.Gateway.TestOpusEncoder do
  @moduledoc false

  def new(options), do: {:ok, Keyword.fetch!(options, :observer)}

  def encode(observer, pcm) do
    send(observer, {:test_pcm_encoded, pcm})
    {:ok, <<0xF8, 0xFF, 0xFE>>}
  end
end
