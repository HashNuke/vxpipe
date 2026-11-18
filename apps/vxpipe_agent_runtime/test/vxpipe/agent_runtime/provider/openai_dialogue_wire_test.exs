defmodule Vxpipe.AgentRuntime.Provider.OpenAIDialogueWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Dialogue, DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @tag capture_log: true
  test "Responses buffered and streaming wire retain schema, instructions and full tools" do
    text = ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Hello."})

    payload = %{
      id: "resp_fixture",
      model: "gpt-6-luna",
      status: "completed",
      usage: %{input_tokens: 20, output_tokens: 10, total_tokens: 30},
      output: [
        %{
          type: "message",
          id: "msg_fixture",
          role: "assistant",
          status: "completed",
          content: [%{type: "output_text", text: text}]
        }
      ]
    }

    for streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn _ ->
          if streaming do
            events = [
              %{
                type: "response.output_text.delta",
                delta: text,
                output_index: 0,
                content_index: 0,
                item_id: "msg_fixture"
              },
              %{type: "response.completed", response: payload}
            ]

            {"text/event-stream",
             Enum.map_join(events, "", fn event ->
               "event: " <> event.type <> "\ndata: " <> JSON.encode!(event) <> "\n\n"
             end)}
          else
            {"application/json", JSON.encode!(payload)}
          end
        end)

      {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: model,
          streaming: streaming,
          generation_options: [base_url: url]
        )

      tools =
        for name <- ["hangup", "lookup"],
            do: %ModelTool{
              name: name,
              description: name,
              input_schema: %{"type" => "object", "properties" => %{}}
            }

      request = %{
        ModelRequest.new([Message.user("Hello")], tools, [], %{})
        | reply_protocol: :mode_message_v1,
          maximum_output_tokens: 100
      }

      result =
        if streaming,
          do: Provider.stream(config, request, fn _ -> :ok end),
          else: Provider.generate(config, request)

      assert {:ok, response} = result
      assert response.text == text
      assert response.tool_calls == []
      assert_receive {:encoded_request, body}
      assert body["text"]["format"]["schema"] == Dialogue.schema()
      assert body["text"]["format"]["strict"] == true
      assert body["max_output_tokens"] == 100
      assert Enum.map(body["tools"], & &1["name"]) == ["hangup", "lookup"]
      assert JSON.encode!(body) =~ "agent_mode"
    end
  end
end
