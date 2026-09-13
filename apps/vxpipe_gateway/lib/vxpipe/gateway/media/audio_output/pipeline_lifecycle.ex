defmodule Vxpipe.Gateway.Media.AudioOutput.PipelineLifecycle do
  @moduledoc false

  alias Vxpipe.Gateway.Media.AudioOutput.State

  @spec launch(State.t()) :: {:ok, State.t()} | {:error, term()}
  def launch(%State{} = state) do
    generation = state.pipeline_generation + 1
    pipeline_id = "#{state.connection_id}:audio-output:#{generation}"

    options =
      Keyword.merge(state.pipeline_options,
        pipeline_id: pipeline_id,
        pipeline_module: state.pipeline,
        owner: self(),
        connection_id: state.connection_id,
        tenant_id: state.identity.tenant_id,
        room_id: state.identity.room_id,
        incarnation_id: state.identity.incarnation_id,
        participant_id: state.identity.participant_id
      )

    case state.pipeline_supervisor.start_audio_output_pipeline(state.connection_id, options) do
      {:ok, pipeline_pid} ->
        {:ok,
         %{
           state
           | pipeline_generation: generation,
             pipeline_id: pipeline_id,
             pipeline_monitor: Process.monitor(pipeline_pid),
             pipeline_pid: pipeline_pid,
             readiness_resource: %{state.readiness_resource | generation: make_ref()},
             pipeline_ready?: false
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec replace(State.t()) :: {:ok, State.t()} | {:error, term(), State.t()}
  def replace(%State{} = state) do
    with :ok <- stop(state),
         :ok <- state.playback_clearer.clear(state.pipeline_options),
         {:ok, state} <- launch(clear_pipeline(state)) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason, clear_pipeline(state)}
    end
  end

  @spec clear_pipeline(State.t()) :: State.t()
  def clear_pipeline(%State{} = state) do
    %{
      state
      | in_flight: nil,
        pipeline_id: nil,
        pipeline_monitor: nil,
        pipeline_pid: nil,
        readiness_resource: %{state.readiness_resource | generation: make_ref()},
        pipeline_ready?: false
    }
  end

  defp stop(%State{pipeline_pid: nil}), do: :ok

  defp stop(%State{} = state) do
    Process.demonitor(state.pipeline_monitor, [:flush])
    state.pipeline_supervisor.stop_audio_output_pipeline(state.connection_id, state.pipeline_pid)
  end
end
