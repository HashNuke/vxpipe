defmodule Vxpipe.CallEngine.Diagnostics.ResponseTiming do
  @moduledoc "Constant-size, turn-owned observation of published text and acknowledged egress."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.RoomAuthority.TurnState

  def new(%CaptureHandoff{} = handoff) do
    if CaptureHandoff.current?(handoff),
      do: %{handoff: handoff, first_response_text: false, first_audio_start: false}
  end

  def new(_), do: nil

  def observe(state, command, output_id, kind)
      when kind in [:first_response_text, :first_audio_start] do
    TurnState.update(state, command, fn turn ->
      case Map.get(turn, :diagnostic_response) do
        %{handoff: handoff} = observation ->
          if Map.fetch!(observation, kind) do
            turn
          else
            {_, correlation, command_id} = TurnState.key(command)

            _ =
              CaptureHandoff.offer(
                handoff,
                {:response_landmark, correlation, command_id, output_id, kind,
                 System.monotonic_time(:microsecond)}
              )

            Map.put(turn, :diagnostic_response, Map.put(observation, kind, true))
          end

        _ ->
          turn
      end
    end)
  end
end
