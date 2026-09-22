defmodule Vxpipe.CallEngine.CallLoad.Playback do
  @moduledoc "Bounded synthetic PCM consumption ledger; never claims human hearing."

  def new(now), do: %{due: now, total_ms: 0, bytes: 0}

  def accept(state, bytes, rate, now) when bytes > 0 and rate > 0 do
    if state.bytes + bytes <= 1_000_000 do
      duration = bytes * 1_000 / (rate * 2)

      {:ok,
       %{
         due: max(now, state.due) + duration,
         total_ms: state.total_ms + duration,
         bytes: state.bytes + bytes
       }}
    else
      {:error, :output_bound}
    end
  end

  def played_ms(state, now), do: floor(max(0, state.total_ms - max(0, state.due - now)))
end
