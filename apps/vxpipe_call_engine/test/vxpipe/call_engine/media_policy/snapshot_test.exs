defmodule Vxpipe.CallEngine.MediaPolicy.SnapshotTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}

  test "membership revisions preserve unchanged service intervals" do
    assert {:ok, before} = Snapshot.prepare(snapshot(1, ["caller", "agent"]), nil)
    assert {:ok, joined} = Snapshot.prepare(snapshot(2, ["caller", "agent", "support"]), before)
    assert {:ok, after_handoff} = Snapshot.prepare(snapshot(3, ["caller", "support"]), joined)

    for policy <- [joined, after_handoff] do
      assert Snapshot.interval(policy, :speech_to_text, "caller") == 1
      assert Snapshot.interval(policy, :audio_input, "caller") == 1
      assert Snapshot.interval(policy, :audio_output, "caller") == 1
      assert Snapshot.interval(policy, :recording) == 1
    end

    assert Snapshot.interval(joined, :audio_input, "support") == 2
  end

  test "a source transcript change affects its recognizer without resetting audio or other sources" do
    routes = %{"caller" => MapSet.new(["agent"]), "support" => MapSet.new(["agent"])}
    initial = snapshot(1, ["caller", "agent", "support"], transcript_routes: routes)
    assert {:ok, initial} = Snapshot.prepare(initial, nil)

    changed =
      snapshot(2, ["caller", "agent", "support"],
        transcript_routes: Map.put(routes, "caller", MapSet.new())
      )

    assert {:ok, changed} = Snapshot.prepare(changed, initial)

    assert Snapshot.interval(changed, :speech_to_text, "caller") == 2
    assert Snapshot.interval(changed, :speech_to_text, "support") == 1
    assert Snapshot.interval(changed, :audio_input, "caller") == 1
    assert Snapshot.interval(changed, :audio_output, "agent") == 1
    assert Snapshot.interval(changed, :recording) == 1
  end

  test "audio route changes affect only the corresponding input and output paths" do
    routes = %{"caller" => MapSet.new(["agent"]), "support" => MapSet.new(["agent"])}

    assert {:ok, initial} =
             Snapshot.prepare(
               snapshot(1, ["caller", "agent", "support"], audio_routes: routes),
               nil
             )

    assert {:ok, changed} =
             Snapshot.prepare(
               snapshot(2, ["caller", "agent", "support"],
                 audio_routes: Map.put(routes, "caller", MapSet.new())
               ),
               initial
             )

    assert Snapshot.interval(changed, :audio_input, "caller") == 2
    assert Snapshot.interval(changed, :audio_input, "support") == 1
    assert Snapshot.interval(changed, :audio_output, "agent") == 2
    assert Snapshot.interval(changed, :audio_output, "support") == 1
    assert Snapshot.interval(changed, :speech_to_text, "caller") == 1
    assert Snapshot.interval(changed, :recording) == 1
  end

  test "restoring permissions creates a new interval instead of accepting old buffered data" do
    assert {:ok, initial} = Snapshot.prepare(snapshot(1, ["caller"]), nil)

    assert {:ok, denied} =
             Snapshot.prepare(
               snapshot(2, ["caller"],
                 record_audio: false,
                 save_transcripts: false,
                 transcript_routes: %{}
               ),
               initial
             )

    assert {:ok, restored} = Snapshot.prepare(snapshot(3, ["caller"]), denied)

    assert Snapshot.interval(restored, :recording) == 3
    assert Snapshot.interval(restored, :speech_to_text, "caller") == 3
    assert Snapshot.interval(restored, :audio_input, "caller") == 3
    assert Snapshot.interval(restored, :audio_output, "caller") == 1
  end

  defp snapshot(revision, present, overrides \\ []) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(present),
      effective:
        struct!(
          Effective,
          Keyword.merge(
            [
              audio_routes: :unrestricted,
              transcript_routes: :unrestricted,
              record_audio: true,
              save_transcripts: true
            ],
            overrides
          )
        )
    }
  end
end
