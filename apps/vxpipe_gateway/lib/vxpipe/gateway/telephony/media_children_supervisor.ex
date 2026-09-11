defmodule Vxpipe.Gateway.Telephony.MediaChildrenSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via(connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_child(String.t(), Supervisor.child_spec()) :: DynamicSupervisor.on_start_child()
  def start_child(connection_id, child_spec) do
    DynamicSupervisor.start_child(via(connection_id), child_spec)
  end

  def start_audio_pipeline(connection_id, options), do: start_pipeline(connection_id, options)

  def stop_audio_pipeline(connection_id, pipeline),
    do: stop_pipeline(connection_id, pipeline)

  def start_room_audio_output_pipeline(connection_id, options),
    do: start_pipeline(connection_id, options)

  def stop_room_audio_output_pipeline(connection_id, pipeline),
    do: stop_pipeline(connection_id, pipeline)

  def start_audio_output_pipeline(connection_id, options),
    do: start_pipeline(connection_id, options)

  def stop_audio_output_pipeline(connection_id, pipeline),
    do: stop_pipeline(connection_id, pipeline)

  defp start_pipeline(connection_id, options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    pipeline_module = Keyword.fetch!(options, :pipeline_module)

    child_spec = %{
      id: {pipeline_module, pipeline_id},
      start: {pipeline_module, :start_link, [Keyword.delete(options, :pipeline_module)]},
      restart: :temporary
    }

    connection_id
    |> via()
    |> DynamicSupervisor.start_child(child_spec)
    |> normalize_pipeline_start()
  end

  defp stop_pipeline(connection_id, pipeline) when is_pid(pipeline) do
    DynamicSupervisor.terminate_child(via(connection_id), pipeline)
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telephony_media_children, connection_id}}}
  end

  defp normalize_pipeline_start({:ok, supervisor, _pipeline}), do: {:ok, supervisor}
  defp normalize_pipeline_start(result), do: result
end
