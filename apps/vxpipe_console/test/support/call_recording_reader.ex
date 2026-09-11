defmodule Vxpipe.Console.TestCallRecordingReader do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecording.Reader

  @impl true
  def read_range({observer, payload}, first, last) do
    send(observer, {:recording_source_read, first, last})
    {:ok, binary_part(payload, first, last - first + 1)}
  end
end
