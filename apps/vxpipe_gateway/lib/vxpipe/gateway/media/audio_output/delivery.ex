defmodule Vxpipe.Gateway.Media.AudioOutput.Delivery do
  @moduledoc false

  alias Vxpipe.Gateway.Media.AudioOutput.State

  @spec drain(State.t()) :: {:ok, State.t()} | {:error, term(), State.t()}
  def drain(%State{pipeline_ready?: true, in_flight: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, frame}, queue} ->
        case safe_push(state.pipeline, state.pipeline_id, frame) do
          :ok -> {:ok, %{state | in_flight: frame, queue: queue}}
          {:error, reason} -> {:error, reason, state}
        end

      {:empty, _queue} ->
        {:ok, state}
    end
  end

  def drain(%State{} = state), do: {:ok, state}

  defp safe_push(pipeline, pipeline_id, frame) do
    pipeline.push(pipeline_id, frame)
  catch
    :exit, _reason -> {:error, :pipeline_unavailable}
  end
end
