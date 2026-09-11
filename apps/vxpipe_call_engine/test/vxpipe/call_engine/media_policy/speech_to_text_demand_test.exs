defmodule Vxpipe.CallEngine.MediaPolicy.SpeechToTextDemandTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot, SpeechToTextDemand}

  test "requires STT for storage or at least one present authorized live recipient" do
    assert SpeechToTextDemand.required?(snapshot(0, ["source"], %{}, true), "source")

    assert SpeechToTextDemand.required?(
             snapshot(1, ["source", "recipient"], %{"source" => ["recipient"]}, false),
             "source"
           )

    refute SpeechToTextDemand.required?(
             snapshot(2, ["source", "recipient"], %{"source" => []}, false),
             "source"
           )

    refute SpeechToTextDemand.required?(
             snapshot(3, ["recipient"], %{"source" => ["recipient"]}, true),
             "source"
           )
  end

  defp snapshot(revision, present, routes, save_transcripts) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(present),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes:
          Map.new(routes, fn {source, recipients} ->
            {source, MapSet.new(recipients)}
          end),
        record_audio: true,
        save_transcripts: save_transcripts
      }
    }
  end
end
