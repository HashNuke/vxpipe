defmodule Vxpipe.CallEngine.Speech.DiagnosticSubscription do
  @moduledoc false
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Speech.{Allocation, Channel, ConversationalSTT}

  def request(allocation, %CaptureHandoff{} = handoff) do
    case GenServer.whereis(Channel.address(allocation)) do
      pid when is_pid(pid) ->
        Process.send(
          pid,
          {:diagnostic_observer_request, allocation.generation, self(), handoff},
          [:nosuspend]
        )

        :ok

      _ ->
        {:error, :unavailable}
    end
  end

  def request_profile(allocation, %CaptureHandoff{} = handoff, canonical \\ nil) do
    case GenServer.whereis(Channel.address(allocation)) do
      pid when is_pid(pid) ->
        Process.send(
          pid,
          {:diagnostic_profile_request, allocation.generation, self(), handoff,
           canonical || allocation.generation},
          [:nosuspend]
        )

        :ok

      _ ->
        {:error, :unavailable}
    end
  end

  def forward(
        {:diagnostic_observer_request, generation, consumer, %CaptureHandoff{} = handoff},
        state
      )
      when generation == state.allocation.generation and consumer == state.consumer and
             state.module in [
               ConversationalSTT,
               Vxpipe.Providers.ElevenLabs.STTSession,
               Vxpipe.Providers.ElevenLabs.ContinuousSTT
             ] do
    # The live consumer may be a wrapper forwarding its consumer's handoff.
    # Keep the original owner/deadline so wrapper forwarding cannot extend capture.
    if state.active? and state.ready_acked? and Allocation.valid?(state.allocation) and
         CaptureHandoff.current?(handoff) do
      Process.send(state.producer, {:diagnostic_observer, generation, handoff, self()}, [
        :nosuspend
      ])
    end

    state
  end

  def forward(
        {:diagnostic_profile_request, generation, consumer, %CaptureHandoff{} = handoff,
         canonical},
        state
      )
      when generation == state.allocation.generation and consumer == state.consumer and
             is_reference(canonical) do
    if state.active? and state.ready_acked? and Allocation.valid?(state.allocation) and
         CaptureHandoff.current?(handoff) do
      if state.module in [
           ConversationalSTT,
           Vxpipe.Providers.ElevenLabs.STTSession,
           Vxpipe.Providers.ElevenLabs.ContinuousSTT
         ] do
        Process.send(
          state.producer,
          {:diagnostic_profile, generation, canonical, handoff, self()},
          [:nosuspend]
        )
      else
        CaptureHandoff.offer(handoff, {:provider_profile, canonical, generation, :unsupported})
      end
    end

    state
  end

  def forward(_invalid, state), do: state
end
