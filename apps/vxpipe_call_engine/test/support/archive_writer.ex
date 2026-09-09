defmodule Vxpipe.CallEngine.TestArchiveWriter do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Fact

  def write(observer, %Fact{} = fact) do
    send(observer, {:test_archive_fact, fact})
    :ok
  end

  def write(observer, fact) do
    send(observer, {:test_archive_write, self(), fact})

    receive do
      {:test_archive_write_result, result} -> result
    after
      5_000 -> {:retry, :test_writer_timeout}
    end
  end
end
