defmodule Vxpipe.Providers.ElevenLabs.ScribeAcknowledgementTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.ElevenLabs.Scribe

  test "readiness retains only echoed profile fields without inventing omitted settings" do
    payload =
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "synthetic",
        "config" => %{
          "model_id" => "scribe_v2_realtime",
          "commit_strategy" => "vad",
          "unrelated" => "must-not-be-retained"
        }
      })

    assert {:ok, {:ready, "synthetic"}} = Scribe.decode(payload, :vad)

    assert {:ok, {:ready, "synthetic", profile}} =
             Scribe.decode_with_profile(payload, :vad, "scribe_v2_realtime")

    assert profile.acknowledged == %{
             "model_id" => "scribe_v2_realtime",
             "commit_strategy" => "vad"
           }

    assert "sample_rate" in profile.missing
    assert "vad_threshold" in profile.missing
    refute Map.has_key?(profile.acknowledged, "unrelated")
  end

  test "empty echoes remain unknown and a missing config object remains invalid" do
    ready = %{"message_type" => "session_started", "session_id" => "synthetic", "config" => %{}}

    assert {:ok, {:ready, "synthetic", %{acknowledged: empty, missing: missing}}} =
             Scribe.decode_with_profile(JSON.encode!(ready), :vad, "scribe_v2_realtime")

    assert empty == %{}
    assert length(missing) == 9

    assert {:error, :invalid_message} =
             Scribe.decode_with_profile(
               JSON.encode!(Map.delete(ready, "config")),
               :vad,
               "scribe_v2_realtime"
             )
  end

  test "complete echo excludes unknown keys and preserves operational mismatch rejection" do
    fields = %{
      "model_id" => "scribe_v2_realtime",
      "sample_rate" => 16_000,
      "audio_format" => "pcm_16000",
      "commit_strategy" => "vad",
      "vad_silence_threshold_secs" => 1.5,
      "vad_threshold" => 0.4,
      "min_speech_duration_ms" => 100,
      "min_silence_duration_ms" => 100,
      "keepalive_interval_ms" => 500
    }

    ready = %{
      "message_type" => "session_started",
      "session_id" => "synthetic",
      "config" => fields
    }

    assert {:ok, {:ready, "synthetic", %{acknowledged: ^fields, missing: []}}} =
             Scribe.decode_with_profile(JSON.encode!(ready), :vad, "scribe_v2_realtime")

    for key <- Map.keys(fields) do
      invalid = put_in(ready, ["config", key], nil)
      assert {:error, :invalid_message} = Scribe.decode(JSON.encode!(invalid), :vad)

      assert {:error, :invalid_message} =
               Scribe.decode_with_profile(JSON.encode!(invalid), :vad, "scribe_v2_realtime")
    end
  end

  test "manual acknowledgement does not invent VAD fields and transcript decode is unchanged" do
    ready = %{
      "message_type" => "session_started",
      "session_id" => "synthetic",
      "config" => %{"commit_strategy" => "manual"}
    }

    assert {:ok,
            {:ready, "synthetic",
             %{acknowledged: %{"commit_strategy" => "manual"}, missing: missing}}} =
             Scribe.decode_with_profile(JSON.encode!(ready), :manual, "scribe_v2_realtime")

    assert length(missing) == 3
    transcript = JSON.encode!(%{"message_type" => "committed_transcript", "text" => "Hello"})

    assert {:ok, {:segment, "Hello"}} =
             Scribe.decode_with_profile(transcript, :vad, "scribe_v2_realtime")
  end

  test "socket sends bounded handshake evidence before the unchanged ready event" do
    state = %{owner: self(), commit_strategy: :vad, model: "scribe_v2_realtime"}

    payload =
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "synthetic",
        "config" => %{"model_id" => "scribe_v2_realtime", "commit_strategy" => "vad"}
      })

    assert {:ok, ^state} =
             Vxpipe.Providers.ElevenLabs.ScribeSocket.handle_frame({:text, payload}, state)

    wire = self()
    assert_receive {:vxpipe_scribe_profile, ^wire, %{acknowledged: fields, missing: missing}}
    assert fields == %{"model_id" => "scribe_v2_realtime", "commit_strategy" => "vad"}
    assert length(missing) == 7
    assert_receive {:vxpipe_scribe_transport, ^wire, {:event, {:ready, "synthetic"}}}
  end

  test "cached acknowledgements reject arbitrary metadata and inconsistent missing-field provenance" do
    payload =
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "synthetic",
        "config" => %{}
      })

    {:ok, {:ready, _, profile}} = Scribe.decode_with_profile(payload, :vad, "scribe_v2_realtime")
    assert {:ok, ^profile} = Scribe.validate_acknowledgement(profile, :vad, "scribe_v2_realtime")

    for invalid <- [
          Map.put(profile, :extra, "not allowed"),
          %{profile | missing: []},
          %{profile | acknowledged: %{"unknown" => "not allowed"}},
          %{profile | missing: profile.missing ++ profile.missing},
          %{profile | acknowledged: %{"vad_threshold" => "0.4"}}
        ] do
      assert :error = Scribe.validate_acknowledgement(invalid, :vad, "scribe_v2_realtime")
    end
  end
end
