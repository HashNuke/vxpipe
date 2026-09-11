defmodule Vxpipe.Gateway.TestRoomAudioOutputPipeline do
  @moduledoc false

  def push(pipeline_id, frame) do
    case Registry.lookup(
           Vxpipe.Gateway.WebRTC.Registry,
           {:test_room_audio_output_pipeline, pipeline_id}
         ) do
      [{pipeline, _value}] ->
        Agent.get(pipeline, fn state ->
          send(state.observer, {:test_room_audio_output_pipeline_push, pipeline_id, frame})
        end)

        :ok

      [] ->
        {:error, :pipeline_unavailable}
    end
  end
end
