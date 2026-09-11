defmodule Vxpipe.Console.TestCallRecordingBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecordingBackend

  @impl true
  def list({observer, %{list: response}}, principal, call_id) do
    send(observer, {:list_call_recordings, principal, call_id})
    response
  end

  def list({observer, response}, principal, call_id) do
    send(observer, {:list_call_recordings, principal, call_id})
    response
  end

  @impl true
  def open({observer, %{open: response}}, principal, call_id, artifact_id) do
    send(observer, {:open_call_recording, principal, call_id, artifact_id})
    response
  end

  def open({observer, response}, principal, call_id, artifact_id) do
    send(observer, {:open_call_recording, principal, call_id, artifact_id})
    response
  end
end
