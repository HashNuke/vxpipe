defmodule Vxpipe.CallEngine.TestCollectingArchiveWriter do
  @moduledoc false

  def write(observer, fact) do
    send(observer, {:test_archive_fact, fact})
    :ok
  end
end
