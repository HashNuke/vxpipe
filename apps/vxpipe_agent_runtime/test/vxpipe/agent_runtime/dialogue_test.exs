defmodule Vxpipe.AgentRuntime.DialogueTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.Dialogue

  test "decodes exactly the common response variants without altering spoken text" do
    assert {:ok, %{agent_mode: :listener, message: nil}} =
             Dialogue.decode(~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}))

    assert {:ok, %{agent_mode: :listener, message: "okayyy"}} =
             Dialogue.decode(~s({"type":"participant_message","participant_id":"agent","message":"okayyy","agent_mode":"listener"}))

    assert {:ok, %{agent_mode: :speaker, message: "  Hi \"世界\"\n"}} =
             Dialogue.decode(JSON.encode!(%{type: "participant_message", participant_id: "agent", agent_mode: "speaker", message: "  Hi \"世界\"\n"}))
  end

  test "accepts the participant envelope shown in settled history without granting identity authority" do
    for {mode, message} <- [{:speaker, "The lookup is running."}, {:listener, "Go ahead"}] do
      {:ok, history} = Vxpipe.AgentRuntime.Message.spoken_assistant("agent", message, mode)

      assert {:ok, %Dialogue{agent_mode: ^mode, message: ^message} = dialogue} =
               Dialogue.decode(history.content)

      refute Map.has_key?(dialogue, :participant_id)
      refute Map.has_key?(dialogue, :type)
    end

    assert {:ok, %Dialogue{agent_mode: :listener, message: nil}} =
             Dialogue.decode(
               ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null})
             )
  end

  test "envelope metadata is bounded and exact, not permission to accept arbitrary fields" do
    valid = %{
      "type" => "participant_message",
      "participant_id" => "agent",
      "agent_mode" => "speaker",
      "message" => "Hello"
    }

    invalid = [
      Map.delete(valid, "type"),
      Map.delete(valid, "participant_id"),
      Map.put(valid, "type", "conversation_summary"),
      Map.put(valid, "participant_id", ""),
      Map.put(valid, "participant_id", nil),
      Map.put(valid, "participant_id", String.duplicate("a", 129)),
      Map.put(valid, "participant_id", "other agent"),
      Map.put(valid, "extra", true)
    ]

    for object <- invalid do
      assert {:error, :invalid_dialogue} = Dialogue.decode(JSON.encode!(object))
    end

    assert {:error, :invalid_dialogue} =
             Dialogue.decode(
               ~s({"type":"participant_message","participant_id":"agent","participant_id":"other","agent_mode":"speaker","message":"Hello"})
             )
  end

  test "rejects the old two-field reply and either missing attribution field" do
    for text <- [~s({"agent_mode":"speaker","message":"Hello"}),
                 ~s({"type":"participant_message","agent_mode":"speaker","message":"Hello"}),
                 ~s({"participant_id":"agent","agent_mode":"speaker","message":"Hello"})] do
      assert {:error, :invalid_dialogue} = Dialogue.decode(text)
    end
  end

  test "rejects malformed responses rather than coercing them into speech or silence" do
    invalid = [
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":null}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener"}),
      ~s({"message":"hello"}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null,"interrupt_agent":false}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null,"message":"hello"}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","agent_mode":"listener","message":null}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"other","message":"hello"}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":true,"message":"hello"}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":3}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":{}}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":[]}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":"  \\n\\t"}),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null} trailing),
      ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}) <> <<0xC2, 0xA0>>,
      ~s([{"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}]),
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
    text = JSON.encode!(%{type: "participant_message", participant_id: "agent", agent_mode: "speaker", message: "hello"})
    assert {:ok, _} = Dialogue.decode(text, byte_size(text))
    assert {:error, :output_too_large} = Dialogue.decode(text, byte_size(text) - 1)
  end

  test "schema has required fields and leaves cross-field admission to the runtime" do
    schema = Dialogue.schema()
    assert schema["type"] == "object"
    assert Enum.sort(schema["required"]) == ["agent_mode", "message", "participant_id", "type"]
    assert schema["additionalProperties"] == false
    assert get_in(schema, ["properties", "agent_mode", "enum"]) == ["listener", "speaker"]
    assert get_in(schema, ["properties", "message", "type"]) == ["string", "null"]
  end
end
