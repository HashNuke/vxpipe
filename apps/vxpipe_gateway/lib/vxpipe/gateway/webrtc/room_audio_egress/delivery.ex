defmodule Vxpipe.Gateway.WebRTC.RoomAudioEgress.Delivery do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.WebRTC.RoomAudioEgress.State

  @spec drain(State.t()) :: {:ok, State.t()} | {:error, term(), State.t()}
  def drain(
        %State{
          drain_pending?: true,
          in_flight: nil,
          pipeline_ready?: true,
          policy: %Snapshot{},
          subscription: subscription
        } = state
      )
      when not is_nil(subscription) do
    state = %{state | drain_pending?: false}

    case safe_take(state.engine, subscription) do
      {:ok, []} ->
        {:ok, state}

      {:ok, [%MixedFrame{} = frame]} ->
        push(frame, state)

      {:ok, _invalid} ->
        {:error, :invalid_mixer_delivery, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def drain(%State{} = state), do: {:ok, state}

  defp push(%MixedFrame{policy_revision: revision}, %State{policy: %{revision: expected}} = state)
       when revision != expected do
    {:error, :stale_policy_revision, state}
  end

  defp push(%MixedFrame{} = frame, %State{} = state) do
    case safe_push(state.pipeline, state.pipeline_id, frame) do
      :ok -> {:ok, %{state | in_flight: {state.pipeline_id, frame.timestamp}}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp safe_take(engine, subscription) do
    engine.take_room_audio(subscription, 1)
  catch
    :exit, _reason -> {:error, :room_audio_unavailable}
  end

  defp safe_push(pipeline, pipeline_id, frame) do
    pipeline.push(pipeline_id, frame)
  catch
    :exit, _reason -> {:error, :pipeline_unavailable}
  end
end
