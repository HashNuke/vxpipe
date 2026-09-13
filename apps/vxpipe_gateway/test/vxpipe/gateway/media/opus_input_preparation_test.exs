defmodule Vxpipe.Gateway.Media.OpusInputPreparationTest do
  use ExUnit.Case, async: true

  alias Membrane.Opus
  alias Vxpipe.Gateway.Media.{InputPrepared, OpusInputPreparation}

  test "defers an early preparation until emitting formats is allowed" do
    reference = make_ref()
    {[], state} = OpusInputPreparation.handle_init(%{}, [])

    assert {[], state} =
             OpusInputPreparation.handle_parent_notification(
               {:prepare, reference, 2},
               %{playback: :stopped},
               state
             )

    assert {[
              stream_format: {:output, %Opus{channels: 2}},
              event: {:output, %InputPrepared{reference: ^reference}}
            ], state} = OpusInputPreparation.handle_playing(%{playback: :playing}, state)

    assert {[], _state} = OpusInputPreparation.handle_playing(%{playback: :playing}, state)
  end
end
