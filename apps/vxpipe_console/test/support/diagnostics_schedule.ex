defmodule Vxpipe.Console.Test.DiagnosticsSchedule do
  @moduledoc "Fixed synthetic provider settlements, independent of response completion."

  def profile(:smoke),
    do: %{
      frames: 192,
      duration_ns: 6_144_000_000,
      measurement_start_ns: 0,
      leading_frames: 64,
      cadence: 64,
      speech_frames: 32
    }

  def profile(:warm),
    do: %{
      frames: 782,
      duration_ns: 25_000_000_000,
      measurement_start_ns: 5_000_000_000,
      leading_frames: 64,
      cadence: 60,
      speech_frames: 24
    }

  def profile(:cold),
    do: %{
      frames: 625,
      duration_ns: 20_000_000_000,
      measurement_start_ns: 0,
      leading_frames: 32,
      cadence: 56,
      speech_frames: 24
    }

  def frame_count(index, rooms, inputs_per_room, mode) do
    plan = profile(mode)
    phase = div(32_000_000 * index, rooms * inputs_per_room)
    div(plan.duration_ns - 1 - phase, 32_000_000) + 1
  end

  def turn_at(index, frame, rooms, inputs_per_room, mode \\ :smoke) do
    plan = profile(mode)
    slot = rem(index, inputs_per_room) * rooms + div(index, inputs_per_room)
    first = plan.leading_frames + div(plan.cadence * (slot + 1), rooms * inputs_per_room)

    if frame >= first and rem(frame - first, plan.cadence) == 0,
      do: div(frame - first, plan.cadence) + 1
  end

  def settlements(index, rooms, inputs_per_room, mode) do
    for frame <- 1..frame_count(index, rooms, inputs_per_room, mode),
        turn = turn_at(index, frame, rooms, inputs_per_room, mode),
        not is_nil(turn),
        do: {frame, turn}
  end

  def measurement_window(pre_launch_us, first_resource_receipt_us, :cold) do
    if not is_integer(first_resource_receipt_us) or
         pre_launch_us < first_resource_receipt_us or
         pre_launch_us - first_resource_receipt_us > 25_000_000,
       do: raise(ArgumentError, "invalid cold preparation boundary")

    %{
      start_us: first_resource_receipt_us,
      end_us: pre_launch_us + 20_000_000,
      ready_by_us: first_resource_receipt_us + 15_000_000
    }
  end

  def measurement_window(pre_launch_us, first_resource_receipt_us, mode) do
    plan = profile(mode)
    stop = pre_launch_us + div(plan.duration_ns, 1_000)

    if not is_integer(first_resource_receipt_us) or first_resource_receipt_us < pre_launch_us or
         first_resource_receipt_us >= stop,
       do: raise(ArgumentError, "invalid measurement boundary receipt")

    %{
      start_us: first_resource_receipt_us,
      end_us: stop,
      ready_by_us: pre_launch_us + div(plan.measurement_start_ns, 1_000)
    }
  end

  def completed_within?(window, settlement_us, completion_us) do
    settlement_us >= window.start_us and completion_us >= settlement_us and
      completion_us < window.end_us
  end
end
