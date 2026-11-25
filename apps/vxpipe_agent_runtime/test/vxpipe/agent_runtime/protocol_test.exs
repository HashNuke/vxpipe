defmodule Vxpipe.AgentRuntime.ProtocolTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Prompt, Protocol}

  test "publication captures dialogue and summary without needing a shared prompt file" do
    directory =
      Path.join(System.tmp_dir!(), "vxpipe-protocol-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    File.write!(Path.join(directory, "llm-dialogue-system.md"), "Dialogue")
    summary = Path.join(directory, "conversation-summary-system.md")
    File.write!(summary, "Summary")

    assert {:ok, snapshot} = Protocol.capture(directory)
    snapshot = snapshot |> JSON.encode!() |> JSON.decode!()
    refute Map.has_key?(snapshot["prompts"], "shared")
    File.rm!(summary)
    assert {:ok, %Prompt{text: "Summary"}} = Protocol.summary_prompt(snapshot)
    assert {:error, :prompt_unavailable} = Protocol.capture(directory)
  end

  test "both agent types use today's shared prompt exactly once for new and historical revisions" do
    assert {:ok, shared} = Prompt.load(:shared)
    stale = "Retired shared instructions"

    historical_shared = %{
      "text" => stale,
      "revision" => Base.encode16(:crypto.hash(:sha256, stale), case: :lower)
    }

    for version <- [:legacy, :mode_message_v1] do
      assert {:ok, current} =
               Protocol.capture(
                 Application.app_dir(:vxpipe_agent_runtime, "priv/prompts"),
                 version
               )

      historical =
        current |> Map.delete("shared_source") |> put_in(["prompts", "shared"], historical_shared)

      assert {:error, :invalid_protocol} = Protocol.validate(Map.delete(current, "shared_source"))

      for snapshot <- [historical, current, nil], kind <- [:llm, :speech_to_speech] do
        dialogue =
          if snapshot != nil and version == :mode_message_v1 and kind == :llm,
            do: [current["prompts"]["llm_dialogue"]["text"]],
            else: []

        expected = Enum.join([shared.text] ++ dialogue ++ ["Authored"], "\n\n")
        assert {:ok, ^expected} = Protocol.instructions(snapshot, "Authored", kind)
      end
    end

    assert {:error, :invalid_protocol} =
             Protocol.instructions(%{"version" => "future"}, "Authored", :llm)

    assert {:error, :invalid_protocol} = Protocol.capture(".", :unknown)
  end
end
