defmodule Vxpipe.CallEngine.OpeningAudio.Fetcher do
  @moduledoc false

  alias Vxpipe.CallEngine.OpeningAudio.Download

  @callback fetch(String.t(), keyword(), term()) :: {:ok, Download.t()} | {:error, term()}
end
