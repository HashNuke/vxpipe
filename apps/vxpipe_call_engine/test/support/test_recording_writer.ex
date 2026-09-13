defmodule Vxpipe.CallEngine.TestRecordingWriter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Recording.Writer

  alias Vxpipe.CallEngine.Readiness.Resource

  @impl true
  def open(stream, options) do
    failure = Keyword.get(options, :failure)

    if (stream.mode == Keyword.get(options, :fail_mode) and failure) &&
         :atomics.get(failure, 1) == 1 do
      send(Keyword.fetch!(options, :observer), {:test_recording_writer_rejected, stream.mode})
      {:error, :test_open_failed}
    else
      opened(stream, options)
    end
  end

  defp opened(stream, options) do
    observer = Keyword.fetch!(options, :observer)
    source = Keyword.fetch!(options, :source)
    send(observer, {:test_recording_writer_opened, self(), source, stream})

    resource =
      Resource.new(:recording_writer, :room, __MODULE__, stream, binding: stream.stream_id)

    {:ok,
     %{
       observer: observer,
       stream_id: stream.stream_id,
       readiness: Keyword.get(options, :readiness),
       readiness_reply: Keyword.get(options, :readiness_reply, :normal),
       resource: resource
     }}
  end

  @impl true
  def readiness(%{readiness_reply: :normal} = handle) do
    status =
      if handle.readiness && :atomics.get(handle.readiness, 1) == 1, do: :failed, else: :ready

    {:ok, handle.resource, status}
  end

  def readiness(%{readiness_reply: reply}), do: reply

  @impl true
  def offer(handle, chunk) do
    send(handle.observer, {:test_recording_chunk, handle.stream_id, chunk})
    :ok
  end
end
