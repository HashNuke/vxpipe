defmodule Vxpipe.AgentRuntime.Provider.ChatReasoningReplayTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  for model <- [
        "deepseek:deepseek-flash",
        "fireworks_ai:accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"
      ],
      streaming <- [false, true] do
    @tag capture_log: true
    test "#{model} preserves private reasoning on tool continuation, streaming=#{streaming}" do
      model = unquote(model)
      streaming = unquote(streaming)
      reasoning = "Synthetic private reasoning: look up the record."

      url =
        DialogueWireServer.start(self(), fn body ->
          call = %{
            id: "call-1",
            type: "function",
            function: %{name: "lookup", arguments: "{}"}
          }

          message = %{
            role: "assistant",
            content: "",
            reasoning_content: reasoning,
            tool_calls: [call]
          }

          payload = %{
            id: "response-1",
            model: body["model"],
            choices: [%{index: 0, message: message, finish_reason: "tool_calls"}]
          }

          if streaming do
            <<first::binary-size(10), rest::binary>> = reasoning

            initial = %{
              payload
              | choices: [
                  %{
                    index: 0,
                    delta: %{role: "assistant", reasoning_content: first},
                    finish_reason: nil
                  }
                ]
            }

            delta = %{
              payload
              | choices: [
                  %{
                    index: 0,
                    delta: %{
                      message
                      | reasoning_content: rest,
                        tool_calls: [Map.put(call, :index, 0)]
                    },
                    finish_reason: "tool_calls"
                  }
                ]
            }

            {"text/event-stream",
             "data: " <>
               JSON.encode!(initial) <>
               "\n\ndata: " <> JSON.encode!(delta) <> "\n\ndata: [DONE]\n\n"}
          else
            {"application/json", JSON.encode!(payload)}
          end
        end)

      [provider, id] = String.split(model, ":", parts: 2)
      provider = if provider == "fireworks_ai", do: "fireworks", else: provider

      assert {:ok, options} =
               Vxpipe.AgentRuntime.ProviderSelection.translate(provider, id, %{}, %{})

      options =
        options
        |> Keyword.put(:api_key, "test-only")
        |> Keyword.put(:streaming, streaming)
        |> Keyword.update!(:generation_options, &Keyword.put(&1, :base_url, url))

      assert {:ok, config} = Provider.new(options)
      assert config.reply_strategy == :portable_json

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
      assert response.text == ""
      assert_receive {:encoded_request, _}

      assistant = Message.assistant(response.text, response.tool_calls, response.provider_replay)

      continuation = %{
        request
        | messages: request.messages ++ [assistant, Message.tool(call, %{"ok" => true})]
      }

      assert {:ok, _} = generate(config, continuation, streaming)
      assert_receive {:encoded_request, body}
      native_assistant = Enum.find(body["messages"], &(&1["role"] == "assistant"))
      assert native_assistant["reasoning_content"] == reasoning
      assert [%{"id" => "call-1"}] = native_assistant["tool_calls"]
      assert [%{"function" => %{"name" => "lookup"}}] = body["tools"]
      refute inspect(response.provider_metadata) =~ reasoning

      for changed <- [
            %{assistant | content: "changed"},
            %{assistant | tool_calls: [%{call | id: "different-call"}]},
            %{assistant | tool_calls: [%{call | arguments: %{"changed" => true}}]},
            %{assistant | tool_calls: [%{call | provider_metadata: %{"changed" => true}}]},
            %{
              assistant
              | provider_replay:
                  Map.put(assistant.provider_replay, "reasoning", String.duplicate("x", 65_536))
            },
            %{assistant | provider_replay: Map.put(assistant.provider_replay, "extra", true)}
          ] do
        assert_raise ArgumentError, fn ->
          Provider.prepare_request(config, %{request | messages: [changed]})
        end
      end

      for changed_model <- [
            %{config.model | id: "other-model"},
            %{config.model | provider_model_id: "other-wire-model"},
            %{config.model | provider: :openrouter}
          ] do
        assert_raise ArgumentError, fn ->
          Provider.prepare_request(%{config | model: changed_model}, %{
            request
            | messages: [assistant]
          })
        end
      end
    end
  end

  defp generate(config, request, false), do: Provider.generate(config, request)
  defp generate(config, request, true), do: Provider.stream(config, request, fn _ -> :ok end)
end
