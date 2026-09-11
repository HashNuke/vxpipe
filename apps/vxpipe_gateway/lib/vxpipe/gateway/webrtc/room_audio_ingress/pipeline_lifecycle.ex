defmodule Vxpipe.Gateway.WebRTC.RoomAudioIngress.PipelineLifecycle do
  @moduledoc false

  alias Vxpipe.Gateway.WebRTC.RoomAudioIngress.State

  @spec launch(State.t()) :: {:ok, State.t()} | {:error, term()}
  def launch(%State{} = state) do
    generation = state.pipeline_generation + 1
    pipeline_id = "#{state.connection_id}:room-audio:#{generation}"

    options =
      Keyword.merge(state.pipeline_options,
        pipeline_id: pipeline_id,
        owner: self(),
        tenant_id: state.identity.tenant_id,
        room_id: state.identity.room_id,
        incarnation_id: state.identity.incarnation_id,
        participant_id: state.identity.participant_id,
        connection_id: state.connection_id,
        clock_origin_ms: state.configuration.clock_origin_ms,
        jitter_latency: state.jitter_latency_ms
      )

    case state.pipeline_supervisor.start_audio_pipeline(state.connection_id, options) do
      {:ok, pipeline_pid} ->
        {:ok,
         %{
           state
           | pipeline_generation: generation,
             pipeline_id: pipeline_id,
             pipeline_monitor: Process.monitor(pipeline_pid),
             pipeline_pid: pipeline_pid,
             pipeline_ready?: false
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec replace(State.t()) :: {:ok, State.t()} | {:error, term(), State.t()}
  def replace(%State{} = state) do
    with :ok <- stop(state),
         {:ok, state} <- launch(clear(state)) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason, clear(state)}
    end
  end

  @spec clear(State.t()) :: State.t()
  def clear(%State{} = state) do
    %{
      state
      | pipeline_id: nil,
        pipeline_monitor: nil,
        pipeline_pid: nil,
        pipeline_ready?: false
    }
  end

  defp stop(%State{pipeline_pid: nil}), do: :ok

  defp stop(%State{} = state) do
    Process.demonitor(state.pipeline_monitor, [:flush])
    state.pipeline_supervisor.stop_audio_pipeline(state.connection_id, state.pipeline_pid)
  end
end
