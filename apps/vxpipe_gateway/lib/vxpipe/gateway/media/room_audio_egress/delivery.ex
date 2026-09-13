defmodule Vxpipe.Gateway.Media.RoomAudioEgress.Delivery do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.Media.RoomAudioEgress.State

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

  defp push(%MixedFrame{} = frame, %State{} = state) do
    if frame.policy_revision ==
         Snapshot.interval(state.policy, :audio_output, state.identity.participant_id) do
      case safe_push(state.pipeline, state.pipeline_id, frame) do
        :ok -> {:ok, %{state | in_flight: {state.pipeline_id, frame.timestamp}}}
        {:error, reason} -> {:error, reason, state}
      end
    else
      {:error, :stale_policy_revision, state}
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
