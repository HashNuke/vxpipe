defmodule Vxpipe.Gateway.TestAudioOutputPipelineSupervisor do
  @moduledoc false

  def start_audio_output_pipeline(_connection_id, options) do
    observer = Keyword.fetch!(options, :test_observer)
    owner = Keyword.fetch!(options, :owner)
    pipeline_id = Keyword.fetch!(options, :pipeline_id)

    starter = self()

    pipeline =
      spawn(fn ->
        monitor = Process.monitor(observer)

        {:ok, _owner} =
          Registry.register(
            Vxpipe.Gateway.Media.Registry,
            {:test_audio_output_pipeline, pipeline_id},
            %{observer: observer}
          )

        send(starter, {:test_audio_output_pipeline_registered, self()})
        await_stop(monitor, observer)
      end)

    receive do
      {:test_audio_output_pipeline_registered, ^pipeline} -> :ok
    end

    send(observer, {:test_audio_output_pipeline_started, pipeline_id, pipeline, owner})
    {:ok, pipeline}
  end

  def stop_audio_output_pipeline(_connection_id, pipeline) do
    [key] = Registry.keys(Vxpipe.Gateway.Media.Registry, pipeline)
    [{^pipeline, %{observer: observer}}] = Registry.lookup(Vxpipe.Gateway.Media.Registry, key)
    {:test_audio_output_pipeline, pipeline_id} = key
    send(observer, {:test_audio_output_pipeline_stopped, pipeline_id, pipeline})
    send(pipeline, :stop)
    :ok
  end

  defp await_stop(monitor, observer) do
    receive do
      :stop -> :ok
      {:DOWN, ^monitor, :process, ^observer, _reason} -> :ok
    end
  end
end
