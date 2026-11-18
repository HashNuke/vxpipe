defmodule Vxpipe.AgentRuntime.Provider.GoogleDialogueWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Dialogue, DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  test "configured Google builtin tools retain portable request encoding", context do
    :ok = Req.Test.set_req_test_to_shared(context)
    owner = self()

    Req.Test.stub(__MODULE__, fn connection ->
      send(owner, {:builtin_request, connection |> Req.Test.raw_body() |> JSON.decode!()})

      Req.Test.json(connection, %{
        candidates: [
          %{
            content: %{
              role: "model",
              parts: [
                %{text: ~s({"agent_mode":"listener","message":null})}
              ]
            },
            finishReason: "STOP"
          }
        ]
      })
    end)

    builtins = [google_grounding: %{enable: true}, google_url_context: true]

    for options <- [
          [provider_options: builtins],
          builtins,
          [provider_options: [google: builtins]]
        ] do
      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: native_model(),
          streaming: false,
          generation_options:
            Keyword.put(options, :req_http_options, plug: {Req.Test, __MODULE__})
        )

      tool = %ModelTool{
        name: "lookup",
        description: "Lookup",
        input_schema: %{"type" => "object", "properties" => %{}}
      }

      request = %{
        ModelRequest.new([Message.user("Hello")], [tool], [], %{})
        | reply_protocol: :mode_message_v1
      }

      assert {:ok, _} = Provider.generate(config, request)
      assert_receive {:builtin_request, body}

      assert [
               %{"google_search" => %{}},
               %{"url_context" => %{}},
               %{"functionDeclarations" => [_]}
             ] =
               body["tools"]

      assert config.reply_strategy == :portable_json
    end
  end

  @tag capture_log: true
  test "private thinking does not contaminate native dialogue text" do
    text = ~s({"agent_mode":"listener","message":null})

    for streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn _ ->
          payload =
            JSON.encode!(%{
              candidates: [
                %{
                  content: %{
                    role: "model",
                    parts: [
                      %{
                        text: "private reasoning",
                        thought: true,
                        thoughtSignature: "private-signature"
                      },
                      %{text: text}
                    ]
                  },
                  finishReason: "STOP"
                }
              ]
            })

          if streaming,
            do: {"text/event-stream", "data: " <> payload <> "\n\n"},
            else: {"application/json", payload}
        end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: native_model(),
          streaming: streaming,
          generation_options: [base_url: url]
        )

      request = %{
        ModelRequest.new([Message.user("Silence")], [], [], %{})
        | reply_protocol: :mode_message_v1
      }

      result =
        if streaming,
          do: Provider.stream(config, request, fn _ -> :ok end),
          else: Provider.generate(config, request)

      assert {:ok, response} = result
      assert response.text == text
    end
  end

  test "SDK-unsupported schema plus tools stays portable without rejecting configuration" do
    for id <- ["gemini-2.5-flash", "unfamiliar-google-model"] do
      {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:google, id)
      assert {:ok, config} = Provider.new(api_key: "test-only", model: model)
      assert config.reply_strategy == :portable_json
      assert Provider.supports_protocol?(config, :mode_message_v1, [])
    end
  end

  @tag capture_log: true
  test "native streaming preserves actual tool calls and their signatures" do
    url =
      DialogueWireServer.start(self(), fn _ ->
        payload = %{
          candidates: [
            %{
              content: %{
                role: "model",
                parts: [
                  %{
                    functionCall: %{name: "structured_output", args: %{}},
                    thoughtSignature: "opaque-signature"
                  }
                ]
              },
              finishReason: "STOP"
            }
          ],
          usageMetadata: %{promptTokenCount: 20, candidatesTokenCount: 10, totalTokenCount: 30}
        }

        {"text/event-stream", "data: " <> JSON.encode!(payload) <> "\n\n"}
      end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: native_model(),
        streaming: true,
        generation_options: [base_url: url]
      )

    tool = %ModelTool{
      name: "structured_output",
      description: "A real authorized tool",
      input_schema: %{"type" => "object", "properties" => %{}}
    }

    request = %{
      ModelRequest.new([Message.user("Use the tool")], [tool], [], %{})
      | reply_protocol: :mode_message_v1
    }

    assert {:ok, response} = Provider.stream(config, request, fn _ -> :ok end)
    assert [call] = response.tool_calls
    assert call.name == "structured_output"
    assert JSON.encode!(call.provider_metadata) =~ "opaque-signature"
  end

  @tag capture_log: true
  test "raw invalid JSON survives native decoding for the shared strict validator" do
    for text <- [
          "```json\n{}\n```",
          ~s({"agent_mode":"speaker","agent_mode":"listener","message":null})
        ],
        streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn _ ->
          payload =
            JSON.encode!(%{
              candidates: [
                %{content: %{role: "model", parts: [%{text: text}]}, finishReason: "STOP"}
              ]
            })

          if streaming,
            do: {"text/event-stream", "data: " <> payload <> "\n\n"},
            else: {"application/json", payload}
        end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: native_model(),
          streaming: streaming,
          generation_options: [base_url: url]
        )

      request = %{
        ModelRequest.new([Message.user("Hello")], [], [], %{})
        | reply_protocol: :mode_message_v1
      }

      result =
        if streaming,
          do: Provider.stream(config, request, fn _ -> :ok end),
          else: Provider.generate(config, request)

      assert {:ok, response} = result
      assert response.text == text
      assert response.tool_calls == []
      assert {:error, :invalid_dialogue} = Dialogue.decode(response.text)
    end
  end

  @tag capture_log: true
  test "Google native schema and complete tools share buffered and streaming wire contracts" do
    text = ~s({"agent_mode":"listener","message":null})

    response = fn _body ->
      payload = %{
        candidates: [%{content: %{role: "model", parts: [%{text: text}]}, finishReason: "STOP"}],
        usageMetadata: %{promptTokenCount: 20, candidatesTokenCount: 10, totalTokenCount: 30}
      }

      {"text/event-stream", "data: " <> JSON.encode!(payload) <> "\n\n"}
    end

    streaming_url = DialogueWireServer.start(self(), response)

    buffered_url =
      DialogueWireServer.start(self(), fn _ ->
        {"application/json",
         JSON.encode!(%{
           candidates: [
             %{content: %{role: "model", parts: [%{text: text}]}, finishReason: "STOP"}
           ]
         })}
      end)

    for {streaming, url} <- [{false, buffered_url}, {true, streaming_url}] do
      assert {:ok, config} =
               Provider.new(
                 api_key: "test-only",
                 model: native_model(),
                 streaming: streaming,
                 generation_options: [base_url: url, max_tokens: 100]
               )

      tools =
        for name <- ["hangup", "lookup"],
            do: %ModelTool{
              name: name,
              description: name,
              input_schema: %{"type" => "object", "properties" => %{}}
            }

      request = %{
        ModelRequest.new([Message.user("Silence")], tools, [], %{})
        | reply_protocol: :mode_message_v1,
          maximum_output_tokens: 100
      }

      result =
        if streaming,
          do: Provider.stream(config, request, fn _ -> :ok end),
          else: Provider.generate(config, request)

      assert {:ok, actual} = result
      assert actual.text == text
      assert actual.tool_calls == []
      assert_receive {:encoded_request, body}
      assert body["generationConfig"]["responseMimeType"] == "application/json"
      assert body["generationConfig"]["responseJsonSchema"] == Dialogue.schema()
      assert body["generationConfig"]["maxOutputTokens"] == 100
      assert body["toolConfig"] in [nil, %{"functionCallingConfig" => %{"mode" => "AUTO"}}]
      [%{"functionDeclarations" => declared}] = body["tools"]
      assert Enum.map(declared, & &1["name"]) == ["hangup", "lookup"]
      assert JSON.encode!(body["systemInstruction"]) =~ "agent_mode"
    end
  end

  defp native_model do
    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:google, "gemini-3.5-flash-lite")
    %{model | capabilities: Map.put(model.capabilities, :json, %{schema: true})}
  end
end
