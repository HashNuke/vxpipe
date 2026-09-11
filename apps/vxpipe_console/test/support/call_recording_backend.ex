defmodule Vxpipe.Console.TestCallRecordingBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecordingBackend

  @impl true
  def open({observer, response}, principal, call_id, artifact_id) do
    send(observer, {:open_call_recording, principal, call_id, artifact_id})
    response
  end
end
