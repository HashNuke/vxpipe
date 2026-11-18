defmodule Vxpipe.Console.Test.UniversalBrowserAssertions do
  @moduledoc "Checks browser-visible dialogue independently of provider speech input."
  import ExUnit.Assertions

  def assert_transcript(evidence, speech) do
    refute Enum.any?(speech, &String.contains?(&1, "agent_mode"))
    assert evidence["output"] == speech
    assert Enum.flat_map(evidence["cases"], & &1["output"]) == speech

    for event <- evidence["timeline"], event["type"] == "bot-output" do
      assert event["data"]["text"] in speech
    end

    :ok
  end

  def assert_google_tool_mode(request) do
    assert get_in(request, ["toolConfig", "functionCallingConfig", "mode"]) in [nil, "AUTO"]
  end
end
