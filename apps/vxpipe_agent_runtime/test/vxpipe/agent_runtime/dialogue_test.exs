defmodule Vxpipe.AgentRuntime.DialogueTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.Dialogue

  test "decodes exactly the common response variants without altering spoken text" do
    assert {:ok, %{agent_mode: :listener, message: nil}} =
             Dialogue.decode(~s({"agent_mode":"listener","message":null}))

    assert {:ok, %{agent_mode: :listener, message: "okayyy"}} =
             Dialogue.decode(~s({"message":"okayyy","agent_mode":"listener"}))

    assert {:ok, %{agent_mode: :speaker, message: "  Hi \"世界\"\n"}} =
             Dialogue.decode(JSON.encode!(%{agent_mode: "speaker", message: "  Hi \"世界\"\n"}))
  end

  test "rejects malformed responses rather than coercing them into speech or silence" do
    invalid = [
      ~s({"agent_mode":"speaker","message":null}),
      ~s({"agent_mode":"listener"}),
      ~s({"message":"hello"}),
      ~s({"agent_mode":"listener","message":null,"interrupt_agent":false}),
      ~s({"agent_mode":"listener","message":null,"message":"hello"}),
      ~s({"agent_mode":"speaker","agent_mode":"listener","message":null}),
      ~s({"agent_mode":"other","message":"hello"}),
      ~s({"agent_mode":true,"message":"hello"}),
      ~s({"agent_mode":"speaker","message":3}),
      ~s({"agent_mode":"speaker","message":{}}),
      ~s({"agent_mode":"speaker","message":[]}),
      ~s({"agent_mode":"listener","message":"  \\n\\t"}),
      ~s({"agent_mode":"listener","message":null),
      ~s({"agent_mode":"listener","message":null} trailing),
      ~s({"agent_mode":"listener","message":null}) <> <<0xC2, 0xA0>>,
      ~s([{"agent_mode":"listener","message":null}]),
      "null",
      "I'm unable to help.",
      "```json\n{\"agent_mode\":\"listener\",\"message\":null}\n```",
      <<255>>
    ]

    for text <- invalid do
      assert {:error, :invalid_dialogue} = Dialogue.decode(text), inspect(text)
    end
  end

  test "bounds the complete object, including escaping and control fields" do
    text = JSON.encode!(%{agent_mode: "speaker", message: "hello"})
    assert {:ok, _} = Dialogue.decode(text, byte_size(text))
    assert {:error, :output_too_large} = Dialogue.decode(text, byte_size(text) - 1)
  end

  test "schema has required fields and leaves cross-field admission to the runtime" do
    schema = Dialogue.schema()
    assert schema["type"] == "object"
    assert Enum.sort(schema["required"]) == ["agent_mode", "message"]
    assert schema["additionalProperties"] == false
    assert get_in(schema, ["properties", "agent_mode", "enum"]) == ["listener", "speaker"]
    assert get_in(schema, ["properties", "message", "type"]) == ["string", "null"]
  end
end
