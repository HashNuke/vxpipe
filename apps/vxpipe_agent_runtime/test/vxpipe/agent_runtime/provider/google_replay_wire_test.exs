defmodule Vxpipe.AgentRuntime.Provider.GoogleReplayWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @tag capture_log: true
  test "signed public parts and empty streaming carriers retain their exact layout" do
    text = ~s({"agent_mode":"speaker","message":"Café"})

    layouts = [
      [%{"text" => text, "thoughtSignature" => "public-signature"}],
      [
        %{"text" => "private", "thought" => true},
        %{"text" => "", "thought" => true, "thoughtSignature" => "trailing-signature"},
        %{"text" => text}
      ],
      [
        %{"text" => "{", "thought" => false, "thoughtSignature" => "first-signature"},
        %{
          "text" => "middle thought",
          "thought" => true,
          "thoughtSignature" => "middle-signature"
        },
        %{"text" => binary_part(text, 1, byte_size(text) - 1)}
      ]
    ]

    for parts <- layouts, streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn _ ->
          if streaming do
            events =
              Enum.map(parts, fn part ->
                %{candidates: [%{content: %{role: "model", parts: [part]}}]}
              end)

            events = events ++ [%{candidates: [%{finishReason: "STOP"}]}]

            {"text/event-stream",
             Enum.map_join(events, "", &("data: " <> JSON.encode!(&1) <> "\n\n"))}
          else
            {"application/json",
             JSON.encode!(%{
               candidates: [%{content: %{role: "model", parts: parts}, finishReason: "STOP"}]
             })}
          end
        end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: "google:gemini-3.5-flash-lite",
          streaming: streaming,
          generation_options: [base_url: url]
        )

      request = %{
        ModelRequest.new([Message.user("Hello")], [], [], %{})
        | reply_protocol: :mode_message_v1
      }

      assert {:ok, response} = generate(config, request, streaming)
      assert response.text == text
      refute response.provider_replay == %{}
      assert_receive {:encoded_request, _}
      assistant = Message.assistant(response.text, [], response.provider_replay)

      assert {:ok, _} =
               generate(
                 config,
                 %{request | messages: request.messages ++ [assistant, Message.user("Again")]},
                 streaming
               )

      assert_receive {:encoded_request, body}
      assert [_, %{"role" => "model", "parts" => ^parts}, _] = body["contents"]
    end
  end

  @tag capture_log: true
  test "runtime IDs are not inserted into signed calls without provider IDs" do
    parts = [
      %{
        "functionCall" => %{"name" => "lookup", "args" => %{}},
        "thoughtSignature" => "call-signature"
      }
    ]

    for streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn body ->
          output =
            if JSON.encode!(body) =~ "functionResponse",
              do: [%{text: ~s({"agent_mode":"listener","message":null})}],
              else: parts

          payload =
            JSON.encode!(%{
              candidates: [%{content: %{role: "model", parts: output}, finishReason: "STOP"}]
            })

          if streaming,
            do: {"text/event-stream", "data: " <> payload <> "\n\n"},
            else: {"application/json", payload}
        end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: "google:gemini-3.5-flash-lite",
          streaming: streaming,
          generation_options: [base_url: url]
        )

      tool = %ModelTool{
        name: "lookup",
        description: "Lookup",
        input_schema: %{"type" => "object", "properties" => %{}}
      }

      request = %{
        ModelRequest.new([Message.user("Lookup")], [tool], [], %{})
        | reply_protocol: :mode_message_v1
      }

      assert {:ok, response} = generate(config, request, streaming)
      assert [call] = response.tool_calls
      assert is_binary(call.id) and call.id != ""
      assert_receive {:encoded_request, _}
      assistant = Message.assistant(response.text, response.tool_calls, response.provider_replay)

      assert {:ok, _} =
               generate(
                 config,
                 %{
                   request
                   | messages:
                       request.messages ++ [assistant, Message.tool(call, %{"ok" => true})]
                 },
                 streaming
               )

      assert_receive {:encoded_request, body}

      assert [
               _,
               %{"role" => "model", "parts" => ^parts},
               %{"parts" => [%{"functionResponse" => result}]}
             ] = body["contents"]

      refute Map.has_key?(result, "id")
    end
  end

  @tag capture_log: true
  test "reasoning on an ordinary native dialogue reply remains private and replayable" do
    text = ~s({"agent_mode":"speaker","message":"Hello."})

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
          model: "google:gemini-3.5-flash-lite",
          streaming: streaming,
          generation_options: [base_url: url]
        )

      request = %{
        ModelRequest.new([Message.user("Hello")], [], [], %{})
        | reply_protocol: :mode_message_v1
      }

      assert {:ok, response} = generate(config, request, streaming)
      assert response.text == text
      assert JSON.encode!(response.provider_replay) =~ "private-signature"
      refute inspect(response.provider_metadata) =~ "private reasoning"
      assistant = Message.assistant(response.text, [], response.provider_replay)
      {_, context, _} = Provider.prepare_request(config, %{request | messages: [assistant]})
      assert [%{role: :system}, %{reasoning_details: [_ | _]}] = context.messages
      refute JSON.encode!(response.provider_replay) =~ "Hello."
    end
  end

  @tag capture_log: true
  test "buffered and streamed private reasoning survives native tool continuation" do
    text = ~s({"agent_mode":"listener","message":null})

    for streaming <- [false, true] do
      url =
        DialogueWireServer.start(self(), fn body ->
          parts =
            if JSON.encode!(body) =~ "functionResponse" do
              [%{text: text}]
            else
              [
                %{
                  text: "private reasoning",
                  thought: true,
                  thoughtSignature: "reasoning-signature"
                },
                %{text: text},
                %{
                  functionCall: %{id: "lookup_1", name: "lookup", args: %{}},
                  thoughtSignature: "call-signature"
                }
              ]
            end

          payload =
            JSON.encode!(%{
              candidates: [%{content: %{role: "model", parts: parts}, finishReason: "STOP"}],
              usageMetadata: %{
                promptTokenCount: 20,
                candidatesTokenCount: 10,
                totalTokenCount: 30
              }
            })

          if streaming,
            do: {"text/event-stream", "data: " <> payload <> "\n\n"},
            else: {"application/json", payload}
        end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: "google:gemini-3.5-flash-lite",
          streaming: streaming,
          generation_options: [base_url: url]
        )

      tool = %ModelTool{
        name: "lookup",
        description: "Lookup",
        input_schema: %{"type" => "object", "properties" => %{}}
      }

      messages = [Message.user("Look up the fixture")]
      request = %{ModelRequest.new(messages, [tool], [], %{}) | reply_protocol: :mode_message_v1}
      assert {:ok, first} = generate(config, request, streaming)
      assert first.text == text
      assert [call] = first.tool_calls
      assert call.id == "lookup_1"
      assert JSON.encode!(first.provider_replay) =~ "reasoning-signature"
      assert_receive {:encoded_request, first_body}

      assistant = Message.assistant(first.text, first.tool_calls, first.provider_replay)

      next = %{
        request
        | messages:
            messages ++
              [
                assistant,
                Message.tool(call, %{"result" => "found"}),
                Message.user("And what is two plus two?")
              ]
      }

      assert {:ok, final} = generate(config, next, streaming)
      assert final.tool_calls == []
      assert final.text == text
      assert_receive {:encoded_request, body}

      assert [initial, %{"role" => "model"}, %{"role" => "user", "parts" => folded}] =
               body["contents"]

      assert [^initial] = first_body["contents"]
      assert [%{"functionResponse" => _}, %{"text" => "And what is two plus two?"}] = folded
      encoded = JSON.encode!(body["contents"])
      assert encoded =~ "reasoning-signature"
      assert encoded =~ "call-signature"
      assert encoded =~ "functionResponse"
      parts = Enum.flat_map(body["contents"], & &1["parts"])

      assert [%{"functionCall" => %{"id" => "lookup_1", "name" => "lookup", "args" => %{}}}] =
               parts
               |> Enum.filter(&Map.has_key?(&1, "functionCall"))
               |> Enum.map(&Map.take(&1, ["functionCall"]))

      assert [
               %{
                 "functionResponse" => %{
                   "id" => "lookup_1",
                   "name" => "lookup",
                   "response" => %{"content" => ~s({"result":"found"})}
                 }
               }
             ] =
               Enum.filter(parts, &Map.has_key?(&1, "functionResponse"))

      for changed <- [%{assistant | content: "redacted"}, %{assistant | tool_calls: []}] do
        assert_raise ArgumentError, fn ->
          Provider.prepare_request(config, %{request | messages: [changed]})
        end
      end

      changed_model = %{config.model | provider_model_id: "different-wire-model"}

      assert_raise ArgumentError, fn ->
        Provider.prepare_request(%{config | model: changed_model}, %{
          request
          | messages: [assistant]
        })
      end
    end
  end

  defp generate(config, request, true), do: Provider.stream(config, request, fn _ -> :ok end)
  defp generate(config, request, false), do: Provider.generate(config, request)
end
