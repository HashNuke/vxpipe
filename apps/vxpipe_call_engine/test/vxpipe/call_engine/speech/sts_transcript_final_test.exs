defmodule Vxpipe.CallEngine.Speech.STSTranscriptFinalTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Event

  test "output transcript snapshots carry an explicit boolean final marker" do
    turn = make_ref()

    for final <- [false, true] do
      assert {:ok, %Event{turn_ref: ^turn, text: "snapshot", final: ^final}} =
               Event.build(:output_transcript, turn_ref: turn, text: "snapshot", final: final)
    end
  end

  test "output transcript finality cannot be an unvalidated truthy value" do
    for final <- ["true", 1, :done, %{}] do
      assert {:error, :invalid_event} =
               Event.build(:output_transcript,
                 turn_ref: make_ref(),
                 text: "snapshot",
                 final: final
               )
    end
  end
end
