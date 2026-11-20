defmodule Vxpipe.Console.Integration.LiveDiagnosticsMicrophoneTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 30_000

  test "Chrome microphone fixture sends human PCM while preserving reference crop bounds" do
    evidence = Vxpipe.Console.Test.LiveDiagnosticsBrowserDriver.verify_microphone!()
    assert evidence["sample_rate"] == 8_000
    assert evidence["source_frames"] == 268_985
    assert evidence["crop_frames"] == 27_200
    assert evidence["track_kind"] == "audio"
    assert evidence["same_track"]
    assert evidence["nonzero_samples"] > 0
    assert evidence["ended"]
    assert evidence["silence_duration"] >= 0.2
  end
end
