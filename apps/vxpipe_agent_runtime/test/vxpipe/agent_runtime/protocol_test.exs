defmodule Vxpipe.AgentRuntime.ProtocolTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Prompt, Protocol}

  test "a serialized protocol pins all instructions independently of later source edits" do
    directory =
      Path.join(System.tmp_dir!(), "vxpipe-protocol-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    for {name, text} <- [
          {"agent-system.md", "Shared"},
          {"llm-dialogue-system.md", "Dialogue"},
          {"conversation-summary-system.md", "Summary"}
        ] do
      File.write!(Path.join(directory, name), text)
    end

    assert {:ok, snapshot} = Protocol.capture(directory)
    snapshot = snapshot |> JSON.encode!() |> JSON.decode!()
    File.write!(Path.join(directory, "agent-system.md"), "Edited")
    File.rm!(Path.join(directory, "conversation-summary-system.md"))

    assert {:ok, "Shared\n\nDialogue\n\nAuthored"} =
             Protocol.instructions(snapshot, "Authored", :llm)

    assert {:ok, "Shared\n\nAuthored"} =
             Protocol.instructions(snapshot, "Authored", :speech_to_speech)

    assert {:ok, %Prompt{text: "Summary"}} = Protocol.summary_prompt(snapshot)
    assert {:error, :prompt_unavailable} = Protocol.capture(directory)

    assert {:error, :invalid_protocol} =
             Protocol.instructions(%{"version" => "future"}, "Authored", :llm)

    assert {:ok, "Legacy"} = Protocol.instructions(nil, "Legacy", :llm)
  end

  test "explicit legacy publications pin prompts without selecting the dialogue overlay" do
    directory = Application.app_dir(:vxpipe_agent_runtime, "priv/prompts")
    assert {:ok, legacy} = Protocol.capture(directory, :legacy)
    assert legacy["version"] == "legacy"
    assert {:ok, text} = Protocol.instructions(legacy, "Authored", :llm)
    assert text == legacy["prompts"]["shared"]["text"] <> "\n\nAuthored"
    refute text =~ legacy["prompts"]["llm_dialogue"]["text"]
    assert {:ok, _summary} = Protocol.summary_prompt(legacy)
    assert {:error, :invalid_protocol} = Protocol.capture(directory, :unknown)
  end
end
