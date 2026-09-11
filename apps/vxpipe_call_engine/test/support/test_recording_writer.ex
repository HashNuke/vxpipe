defmodule Vxpipe.CallEngine.TestRecordingWriter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Recording.Writer

  @impl true
  def open(stream, options) do
    observer = Keyword.fetch!(options, :observer)
    source = Keyword.fetch!(options, :source)
    send(observer, {:test_recording_writer_opened, self(), source, stream})
    {:ok, %{observer: observer, stream_id: stream.stream_id}}
  end

  @impl true
  def offer(handle, chunk) do
    send(handle.observer, {:test_recording_chunk, handle.stream_id, chunk})
    :ok
  end
end
