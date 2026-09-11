defmodule Vxpipe.Gateway.TestRoomAudioOutputPipelineSupervisor do
  @moduledoc false

  def start_room_audio_output_pipeline(_connection_id, options) do
    observer = Keyword.fetch!(options, :test_observer)
    owner = Keyword.fetch!(options, :owner)
    pipeline_id = Keyword.fetch!(options, :pipeline_id)

    {:ok, pipeline} =
      Agent.start_link(
        fn -> %{observer: observer, pipeline_id: pipeline_id} end,
        name:
          {:via, Registry,
           {Vxpipe.Gateway.WebRTC.Registry, {:test_room_audio_output_pipeline, pipeline_id}}}
      )

    send(observer, {:test_room_audio_output_pipeline_started, pipeline_id, pipeline, owner})
    {:ok, pipeline}
  end

  def stop_room_audio_output_pipeline(_connection_id, pipeline) do
    %{observer: observer, pipeline_id: pipeline_id} = Agent.get(pipeline, & &1)
    send(observer, {:test_room_audio_output_pipeline_stopped, pipeline_id, pipeline})
    Agent.stop(pipeline)
  end
end
