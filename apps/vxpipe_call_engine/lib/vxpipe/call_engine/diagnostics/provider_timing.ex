defmodule Vxpipe.CallEngine.Diagnostics.ProviderTiming do
  @moduledoc "Transient same-VM provider landmarks, fenced by diagnostic authority and free of text."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff

  def stamp(%CaptureHandoff{} = handoff) do
    received_us = System.monotonic_time(:microsecond)
    if CaptureHandoff.current?(handoff), do: {handoff.token, received_us}
  end

  def stamp(_disabled), do: nil

  def emit(%CaptureHandoff{} = handoff, generation, turn, kind, {token, time}, samples)
      when token == handoff.token do
    _ = CaptureHandoff.offer(handoff, {:provider_landmark, generation, turn, kind, time, samples})
    :ok
  end

  def emit(_handoff, _generation, _turn, _kind, _stamp, _samples), do: :ok
end
