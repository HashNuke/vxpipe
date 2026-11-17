defmodule Vxpipe.Calls.ArchiveSanitizerTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ArchiveSanitizer

  test "transcript retention applies to nested dialogue, cues, summaries and raw copies" do
    payload = %{
      "content" => %{"message" => "private"},
      "metadata" => [
        %{
          "message" => "private",
          "summary" => "private",
          "cue" => %{"text" => "private"},
          "raw_response" => "{\"message\":\"private\"}",
          "id" => "kept"
        }
      ]
    }

    assert ArchiveSanitizer.filter_payload(payload, :agent_output_generated, %{
             "save_transcripts" => false
           }) ==
             %{"metadata" => [%{"id" => "kept"}]}

    assert ArchiveSanitizer.filter_payload(payload, :agent_output_generated, %{
             "save_transcripts" => true
           }) == payload

    assert ArchiveSanitizer.filter_payload(payload, :tool_call_completed, %{
             "save_transcripts" => false
           }) == payload
  end
end
