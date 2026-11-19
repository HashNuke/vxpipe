defmodule Vxpipe.CallEngine.Diagnostics.SourceDiscovery do
  @moduledoc "One bounded, prospective source announcement after provider acceptance."
  alias Vxpipe.CallEngine.Capability.SpeechToText.State
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  @timeout_ms 250

  def arm(state, %CaptureHandoff{owner: owner} = handoff) when owner == self() do
    with nil <- state.private_allocation,
         true <- state.policy != nil,
         {:ok, %{status: :ready, allocation_generation: generation}} <- State.input_binding(state),
         true <- is_reference(generation) and CaptureHandoff.current?(handoff),
         nil <- state.diagnostic_probe do
      token = make_ref()

      probe = %{
        handoff: handoff,
        token: token,
        generation: generation,
        revision: state.policy.revision,
        deadline: System.monotonic_time(:millisecond) + @timeout_ms,
        timer: Process.send_after(self(), {:diagnostic_probe_expired, token}, @timeout_ms)
      }

      {:ok, %{state | diagnostic_probe: probe}}
    else
      _ -> {:error, :unavailable}
    end
  end

  def arm(_state, _handoff), do: {:error, :unavailable}

  def accept(%{diagnostic_probe: nil} = state, _frame), do: state

  def accept(%{diagnostic_probe: probe} = state, frame) do
    if pending?(probe) and state.private_allocation == nil and state.policy != nil and
         state.policy.revision == probe.revision and state.session != nil and
         state.session.generation == probe.generation do
      mode =
        if state.provider_module == Vxpipe.CallEngine.Speech.ConversationalSTT and
             state.descriptor.speech_start_evidence == :local_acoustic,
           do: :operational_reuse,
           else: :benchmark_only

      _ =
        CaptureHandoff.offer(
          probe.handoff,
          {:source_ready, probe.generation, probe.revision, frame.track_id,
           Map.get(frame, :source_epoch), frame.codec, frame.sample_rate, frame.channels, mode}
        )
    else
      CaptureHandoff.close(probe.handoff)
    end

    Process.cancel_timer(probe.timer)
    %{state | diagnostic_probe: nil}
  end

  def cancel(%{diagnostic_probe: nil} = state), do: state

  def cancel(%{diagnostic_probe: probe} = state) do
    Process.cancel_timer(probe.timer)
    CaptureHandoff.close(probe.handoff)
    %{state | diagnostic_probe: nil}
  end

  def expire(%{diagnostic_probe: %{token: token} = probe} = state, token) do
    CaptureHandoff.close(probe.handoff)
    %{state | diagnostic_probe: nil}
  end

  def expire(state, _token), do: state

  defp pending?(nil), do: false

  defp pending?(probe),
    do:
      System.monotonic_time(:millisecond) < probe.deadline and
        CaptureHandoff.current?(probe.handoff)
end
