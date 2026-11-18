defmodule Vxpipe.Console.UniversalBrowserAssertionsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.UniversalBrowserAssertions, as: Checks

  test "clean browser text matches the actual TTS input" do
    assert Checks.assert_transcript(evidence(), ["Four"]) == :ok
  end

  for surface <- ["output", "cases", "timeline"] do
    test "rejects control JSON on browser #{surface} despite clean TTS" do
      leak = ~s({"agent_mode":"speaker","message":"Four"})

      changed =
        case unquote(surface) do
          "output" -> [leak]
          "cases" -> [%{"output" => [leak]}]
          "timeline" -> [%{"type" => "bot-output", "data" => %{"text" => leak}}]
        end

      assert_raise ExUnit.AssertionError, fn ->
        Checks.assert_transcript(Map.put(evidence(), unquote(surface), changed), ["Four"])
      end
    end
  end

  test "Google tools remain optional rather than forced or disabled" do
    Checks.assert_google_tool_mode(%{})

    for mode <- ["AUTO", "ANY", "NONE"] do
      request = %{"toolConfig" => %{"functionCallingConfig" => %{"mode" => mode}}}

      if mode == "AUTO" do
        Checks.assert_google_tool_mode(request)
      else
        assert_raise ExUnit.AssertionError, fn -> Checks.assert_google_tool_mode(request) end
      end
    end
  end

  defp evidence do
    %{
      "output" => ["Four"],
      "cases" => [%{"output" => ["Four"]}],
      "timeline" => [%{"type" => "bot-output", "data" => %{"text" => "Four"}}]
    }
  end
end
