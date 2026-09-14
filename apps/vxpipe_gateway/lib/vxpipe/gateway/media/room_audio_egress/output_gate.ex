defmodule Vxpipe.Gateway.Media.RoomAudioEgress.OutputGate do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.Media.SharedOutputPipeline

  def binding(%{pipeline: SharedOutputPipeline, subscription: subscription} = state)
      when not is_nil(subscription) do
    case Keyword.get(state.pipeline_options, :output_sink) do
      output when is_pid(output) ->
        {:ok,
         %{
           engine: state.engine,
           subscription: subscription,
           output: output,
           pipeline: state.pipeline_pid,
           interval:
             if(state.policy,
               do: Snapshot.interval(state.policy, :audio_output, state.identity.participant_id)
             )
         }}

      _missing ->
        {:error, :output_unavailable}
    end
  end

  def binding(_state), do: {:error, :unsupported_output_gate}

  # Observe and gate dependencies outside the egress loop, which must remain available for
  # policy acknowledgements and completion of a room frame discarded by native clear.
  def change(egress, action, generation) do
    with {:ok, binding} <- GenServer.call(egress, :output_gate_binding, 1_000),
         {:ok, route, :ready} <- SharedOutputPipeline.readiness(binding.pipeline) do
      apply_gate(egress, binding, route, action, generation)
    else
      {:ok, _route, _status} -> {:error, :output_not_ready}
      {:error, _reason} = error -> error
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp apply_gate(egress, binding, route, :hold, generation) do
    with :ok <- binding.engine.hold_room_audio(binding.subscription, generation),
         :ok <- OutputSink.hold(binding.output, generation),
         do: revalidate(egress, binding, route)
  end

  defp apply_gate(egress, binding, route, :release, generation) do
    with :ok <- OutputSink.release(binding.output, generation) do
      case release_subscription(egress, binding, route, generation) do
        :ok ->
          :ok

        _failure ->
          GenServer.cast(egress, :output_release_failed)
          {:error, :output_release_uncertain}
      end
    end
  end

  defp release_subscription(egress, binding, route, generation) do
    with :ok <- binding.engine.release_room_audio(binding.subscription, generation),
         do: revalidate(egress, binding, route)
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp revalidate(egress, binding, route) do
    with {:ok, ^binding} <- GenServer.call(egress, :output_gate_binding, 1_000),
         {:ok, ^route, :ready} <- SharedOutputPipeline.readiness(binding.pipeline) do
      :ok
    else
      _changed -> {:error, :stale_output_binding}
    end
  end
end
