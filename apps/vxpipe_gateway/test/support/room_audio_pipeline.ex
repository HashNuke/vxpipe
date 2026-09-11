defmodule Vxpipe.Gateway.TestRoomAudioPipeline do
  @moduledoc false

  def push(pipeline_id, frame) do
    [{pipeline, _value}] =
      Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:test_room_audio_pipeline, pipeline_id})

    Agent.get(pipeline, fn observer ->
      send(observer, {:test_room_audio_pipeline_push, pipeline, frame})
    end)

    :ok
  end
end
