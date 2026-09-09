defmodule Vxpipe.CallEngine.TestBlockingArchiveWriter do
  @moduledoc false

  def write(observer, fact) do
    send(observer, {:test_archive_write, self(), fact})

    receive do
      {:test_archive_write_result, result} -> result
    after
      5_000 -> {:retry, :test_writer_timeout}
    end
  end
end
