defmodule Vxpipe.Console.TestCallRecordingObjectReader do
  @moduledoc false

  def read_range(reference, first, last, options) do
    observer = Keyword.fetch!(options, :observer)
    payload = Keyword.fetch!(options, :payload)
    send(observer, {:read_call_recording_object, reference, first, last, options})
    {:ok, binary_part(payload, first, last - first + 1)}
  end
end
