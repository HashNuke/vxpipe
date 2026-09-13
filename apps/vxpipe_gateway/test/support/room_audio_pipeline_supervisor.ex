defmodule Vxpipe.Gateway.TestRoomAudioPipelineSupervisor do
  @moduledoc false

  def start_audio_pipeline(_connection_id, options) do
    observer = Keyword.fetch!(options, :test_observer)
    pipeline_id = Keyword.fetch!(options, :pipeline_id)

    if Keyword.get(options, :test_fail_generation) == generation(pipeline_id) do
      {:error, :test_pipeline_unavailable}
    else
      start_pipeline(observer, pipeline_id, options)
    end
  end

  defp start_pipeline(observer, pipeline_id, options) do
    {:ok, pipeline} =
      Agent.start_link(
        fn ->
          %{
            observer: observer,
            status: :preparing,
            resource:
              Vxpipe.CallEngine.Readiness.Resource.new(
                :audio_input,
                {:participant, Keyword.fetch!(options, :participant_id)},
                Vxpipe.Gateway.TestRoomAudioPipeline,
                options,
                binding: Keyword.fetch!(options, :connection_id)
              )
          }
        end,
        name:
          {:via, Registry,
           {Vxpipe.Gateway.WebRTC.Registry, {:test_room_audio_pipeline, pipeline_id}}}
      )

    send(observer, {:test_room_audio_pipeline_started, pipeline_id, pipeline})
    {:ok, pipeline}
  end

  def stop_audio_pipeline(_connection_id, pipeline) do
    Agent.stop(pipeline)
    :ok
  end

  defp generation(pipeline_id) do
    pipeline_id
    |> String.split(":")
    |> List.last()
    |> String.to_integer()
  end
end
