defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Clock do
  @moduledoc """
  Pure drift-corrected frame scheduler for the Morse duplex provider.

  Frames are computed from a monotonic origin, never by counting ticks, so a
  late tick emits exactly the audio that is due. Catch-up is bounded: a tick
  emits at most `max_catch_up_frames`, and a larger backlog moves the origin
  forward and reports a stall rather than bursting. A stalled session resumes at
  real time; it does not replay the stall.
  """

  @default_frame_ms 20
  @default_max_catch_up_frames 5

  @doc """
  Returns `{frames_due, new_origin_ms, new_emitted_frames, stalled?}` for the
  elapsed audio time between `origin_ms` and `now_ms`.
  """
  @spec frames_due(
          integer(),
          integer(),
          non_neg_integer(),
          pos_integer(),
          pos_integer()
        ) :: {non_neg_integer(), integer(), non_neg_integer(), boolean()}
  def frames_due(
        origin_ms,
        now_ms,
        emitted_frames,
        frame_ms \\ @default_frame_ms,
        max_catch_up_frames \\ @default_max_catch_up_frames
      )
      when is_integer(origin_ms) and is_integer(now_ms) and is_integer(emitted_frames) and
             emitted_frames >= 0 and is_integer(frame_ms) and frame_ms > 0 and
             is_integer(max_catch_up_frames) and max_catch_up_frames > 0 do
    due = max(div(now_ms - origin_ms, frame_ms) - emitted_frames, 0)

    if due <= max_catch_up_frames do
      {due, origin_ms, emitted_frames + due, false}
    else
      emitted = emitted_frames + max_catch_up_frames
      {max_catch_up_frames, now_ms - emitted * frame_ms, emitted, true}
    end
  end
end
