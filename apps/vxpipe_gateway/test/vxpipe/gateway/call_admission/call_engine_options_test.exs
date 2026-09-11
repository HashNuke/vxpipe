defmodule Vxpipe.Gateway.CallAdmission.CallEngineOptionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions

  test "passes trusted recording configuration to call startup" do
    recording = [
      enabled: true,
      targets: [:full_mix],
      writer: {TestWriter, [object_store: TestStore]},
      maximum_pull_frames: 4
    ]

    assert CallEngineOptions.build(recording: recording) == [
             archive: [enabled: false],
             recording: recording
           ]
  end
end
