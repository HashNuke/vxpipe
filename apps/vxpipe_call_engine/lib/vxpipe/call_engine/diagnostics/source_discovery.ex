defmodule Vxpipe.CallEngine.Diagnostics.SourceDiscovery do
  @moduledoc "One bounded, prospective source announcement after provider acceptance."
  alias Vxpipe.CallEngine.Capability.SpeechToText.State
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsProjection}
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
        intervals: State.diagnostic_intervals(state),
        deadline: System.monotonic_time(:millisecond) + @timeout_ms,
        timer: Process.send_after(self(), {:diagnostic_probe_expired, token}, @timeout_ms)
      }

      {:ok, %{state | diagnostic_probe: probe, diagnostic_source: nil}}
    else
      _ -> {:error, :unavailable}
    end
  end

  def arm(_state, _handoff), do: {:error, :unavailable}

  def request_profile(state, %CaptureHandoff{owner: owner} = handoff) when owner == self() do
    with true <- state.private_allocation == nil and state.policy != nil and state.session != nil,
         {:ok, evidence} <- profile_evidence(state, handoff),
         true <-
           State.diagnostic_intervals(state) == evidence.intervals and
             state.session.generation == evidence.generation do
      Vxpipe.CallEngine.Speech.DiagnosticSubscription.request_profile(state.session, handoff)
    else
      _ -> {:error, :unavailable}
    end
  end

  def request_profile(_state, _handoff), do: {:error, :unavailable}

  defp profile_evidence(%{diagnostic_probe: %{handoff: handoff} = probe}, handoff),
    do: if(pending?(probe), do: {:ok, probe}, else: :error)

  defp profile_evidence(%{diagnostic_probe: nil, diagnostic_source: proof} = state, handoff)
       when not is_nil(proof) do
    if handoff.token == proof.token and CaptureHandoff.current?(handoff) and
         validate(state, proof.generation, proof.intervals, proof.source, handoff, proof.token),
       do: {:ok, proof},
       else: :error
  end

  defp profile_evidence(_state, _handoff), do: :error

  def accept(state, frame) do
    state = check_source(state, frame)
    announce(state, frame)
  end

  def validate(state, generation, intervals, source, handoff, token) do
    case state.diagnostic_source do
      %{
        generation: ^generation,
        intervals: ^intervals,
        source: ^source,
        token: ^token,
        grant: grant,
        projection: projection,
        deadline: deadline
      } ->
        state.session != nil and state.session.generation == generation and
          state.policy != nil and State.diagnostic_intervals(state) == intervals and
          handoff.grant == grant and handoff.projection == projection and
          System.monotonic_time(:millisecond) < deadline and
          SettingsProjection.grant(projection) == {:ok, grant}

      _ ->
        false
    end
  end

  defp check_source(%{diagnostic_source: nil} = state, _frame), do: state

  defp check_source(%{diagnostic_source: proof} = state, frame) do
    if state.session != nil and state.session.generation == proof.generation and
         state.policy != nil and State.diagnostic_intervals(state) == proof.intervals and
         proof.source == %{
           track_id: Map.get(frame, :track_id),
           source_epoch: Map.get(frame, :source_epoch)
         } and
         System.monotonic_time(:millisecond) < proof.deadline and
         SettingsProjection.grant(proof.projection) == {:ok, proof.grant},
       do: state,
       else: %{state | diagnostic_source: nil}
  end

  defp announce(%{diagnostic_probe: nil} = state, _frame), do: state

  defp announce(%{diagnostic_probe: probe} = state, frame) do
    proof =
      if pending?(probe) and state.private_allocation == nil and state.policy != nil and
           State.diagnostic_intervals(state) == probe.intervals and state.session != nil and
           state.session.generation == probe.generation do
        announce_source(state, probe, frame)
      else
        CaptureHandoff.close(probe.handoff)
        nil
      end

    Process.cancel_timer(probe.timer)
    %{state | diagnostic_probe: nil, diagnostic_source: proof}
  end

  defp announce_source(state, probe, frame) do
    mode =
      if state.provider_module == Vxpipe.CallEngine.Speech.ConversationalSTT and
           state.descriptor.speech_start_evidence == :local_acoustic,
         do: :operational_reuse,
         else: :benchmark_only

    source = %{track_id: Map.get(frame, :track_id), source_epoch: Map.get(frame, :source_epoch)}

    packet =
      {:source_ready, probe.generation, probe.intervals, Map.get(frame, :track_id),
       source.source_epoch, frame.codec, frame.sample_rate, frame.channels, mode}

    case CaptureHandoff.offer(probe.handoff, packet) do
      :ok ->
        %{
          generation: probe.generation,
          intervals: probe.intervals,
          source: %{source | track_id: :binary.copy(source.track_id)},
          token: probe.handoff.token,
          grant: probe.handoff.grant,
          projection: probe.handoff.projection,
          deadline: System.monotonic_time(:millisecond) + 5_000
        }

      _ ->
        nil
    end
  end

  def cancel(%{diagnostic_probe: nil} = state), do: %{state | diagnostic_source: nil}

  def cancel(%{diagnostic_probe: probe} = state) do
    Process.cancel_timer(probe.timer)
    CaptureHandoff.close(probe.handoff)
    %{state | diagnostic_probe: nil, diagnostic_source: nil}
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
