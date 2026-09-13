defmodule Vxpipe.Gateway.TestRoomAudioPipeline do
  @moduledoc false

  def push(pipeline_id, frame) do
    [{pipeline, _value}] =
      Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:test_room_audio_pipeline, pipeline_id})

    Agent.get(pipeline, fn state ->
      send(state.observer, {:test_room_audio_pipeline_push, pipeline, frame})
    end)

    :ok
  end

  def readiness(pipeline_id) do
    [{pipeline, _value}] =
      Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:test_room_audio_pipeline, pipeline_id})

    Agent.get(pipeline, &{:ok, &1.resource, &1.status})
  end

  def set_status(pipeline, status), do: Agent.update(pipeline, &%{&1 | status: status})
end
