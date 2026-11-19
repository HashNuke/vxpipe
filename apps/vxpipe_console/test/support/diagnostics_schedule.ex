defmodule Vxpipe.Console.Test.DiagnosticsSchedule do
  @moduledoc "Fixed synthetic provider settlements, independent of response completion."

  def turn_at(index, frame, rooms, inputs_per_room) do
    # Spread rooms across the window, with the humans in each room half a window apart.
    slot = rem(index, inputs_per_room) * rooms + div(index, inputs_per_room)
    first = 64 + div(64 * (slot + 1), rooms * inputs_per_room)

    if frame >= first and rem(frame - first, 64) == 0,
      do: div(frame - first, 64) + 1
  end
end
