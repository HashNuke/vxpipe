defmodule Vxpipe.Gateway.TestAudioOutputPipeline do
  @moduledoc false

  def push(pipeline_id, frame) do
    case Registry.lookup(
           Vxpipe.Gateway.Media.Registry,
           {:test_audio_output_pipeline, pipeline_id}
         ) do
      [{_pipeline, %{observer: observer}}] ->
        send(observer, {:test_audio_output_pipeline_push, pipeline_id, frame})
        :ok

      [] ->
        {:error, :pipeline_unavailable}
    end
  end
end
