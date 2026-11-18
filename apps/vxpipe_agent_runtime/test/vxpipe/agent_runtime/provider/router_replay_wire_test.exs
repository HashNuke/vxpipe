defmodule Vxpipe.AgentRuntime.Provider.RouterReplayWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  for provider <- ["openrouter", "zenmux"], streaming <- [false, true] do
    @tag capture_log: true
    test "#{provider} requires a nonblank reported replay origin streaming=#{streaming}" do
      streaming = unquote(streaming)
      details = [%{"type" => "reasoning.encrypted", "data" => "synthetic-opaque"}]

      for model <- [nil, "", " \t\n"] do
        url =
          DialogueWireServer.start(self(), fn body ->
            payload(Map.put(body, "model", model), details, streaming)
          end)

        config = config(unquote(provider), streaming, url)
        assert {:error, :invalid_provider_response} = generate(config, request(), streaming)
      end
    end

    @tag capture_log: true
    test "#{provider} rejects malformed private details before tool admission streaming=#{streaming}" do
      streaming = unquote(streaming)

      for details <- [
            %{"unexpected" => "object"},
            "invalid",
            42,
            [nil],
            [%{"type" => "reasoning.encrypted", "data" => 123}]
          ] do
        url = DialogueWireServer.start(self(), &payload(&1, details, streaming))
        config = config(unquote(provider), streaming, url)
        assert {:error, :invalid_provider_response} = generate(config, request(), streaming)
      end

      for field <- [:reasoning, :reasoning_content],
          value <- [123, %{}],
          extra <- [%{}, %{reasoning_details: [%{type: "reasoning.encrypted", data: "opaque"}]}] do
        url = DialogueWireServer.start(self(), &payload(&1, value, streaming, field, extra))
        config = config(unquote(provider), streaming, url)
        assert {:error, :invalid_provider_response} = generate(config, request(), streaming)
      end
    end

    @tag capture_log: true
    test "#{provider} rejects a changed origin before another tool dispatch streaming=#{streaming}" do
      streaming = unquote(streaming)
      details = [%{"type" => "reasoning.encrypted", "data" => "synthetic-opaque", "index" => 0}]

      url =
        DialogueWireServer.start(self(), fn body ->
          if Enum.any?(body["messages"], &(&1["role"] == "assistant")) do
            payload(Map.put(body, "model", "third/model"), [], streaming)
          else
            payload(body, details, streaming)
          end
        end)

      config = config(unquote(provider), streaming, url)
      assert {:ok, response} = generate(config, request(), streaming)
      [call] = response.tool_calls
      assistant = Message.assistant(response.text, [call], response.provider_replay)

      continuation = %{
        request()
        | messages: [Message.user("Lookup"), assistant, Message.tool(call, %{"ok" => true})]
      }

      assert {:error, :invalid_provider_response} = generate(config, continuation, streaming)
    end

    @tag capture_log: true
    test "#{provider} reports the actual routed model without private replay streaming=#{streaming}" do
      streaming = unquote(streaming)

      url =
        DialogueWireServer.start(self(), fn body ->
          payload(Map.put(body, "model", "other/model"), [], streaming)
        end)

      config = config(unquote(provider), streaming, url)
      assert {:ok, response} = generate(config, request(), streaming)
      assert response.provider_metadata.model == "other/model"
    end

    @tag capture_log: true
    test "#{provider} preserves ordered opaque details streaming=#{streaming}" do
      provider = unquote(provider)
      streaming = unquote(streaming)

      details = [
        %{
          "type" => "reasoning.text",
          "text" => nil,
          "signature" => nil,
          "id" => nil,
          "index" => 0
        },
        %{
          "type" => "reasoning.text",
          "text" => "Synthetic thought",
          "signature" => nil,
          "id" => nil,
          "format" => "google-gemini-v1",
          "index" => 0
        },
        %{
          "type" => "reasoning.encrypted",
          "data" => "synthetic-opaque",
          "id" => "r1",
          "format" => "google-gemini-v1",
          "index" => 1
        }
      ]

      url = DialogueWireServer.start(self(), &payload(&1, details, streaming))
      config = config(provider, streaming, url)
      request = request()
      assert {:ok, response} = generate(config, request, streaming)
      assert [call] = response.tool_calls
      assert response.text == ""
      assert_receive {:encoded_request, _}
      assistant = Message.assistant(response.text, [call], response.provider_replay)

      continuation = %{
        request
        | messages: request.messages ++ [assistant, Message.tool(call, %{"ok" => true})]
      }

      assert {:ok, _} = generate(config, continuation, streaming)
      assert_receive {:encoded_request, body}
      native = Enum.find(body["messages"], &(&1["role"] == "assistant"))
      assert native["reasoning_details"] == details
      assert [%{"id" => "call-1"}] = native["tool_calls"]
      assert [%{"function" => %{"name" => "lookup"}}] = body["tools"]
      refute inspect(response.provider_metadata) =~ "synthetic-opaque"

      for changed <- [
            %{config | model: %{config.model | id: "another/model"}},
            %{
              config
              | generation_options: Keyword.put(config.generation_options, :temperature, 0.9)
            }
          ] do
        assert_raise ArgumentError, fn -> Provider.prepare_request(changed, continuation) end
      end
    end

    @tag capture_log: true
    test "#{provider} pins a routed origin while private history remains streaming=#{streaming}" do
      streaming = unquote(streaming)
      details = [%{"type" => "reasoning.encrypted", "data" => "synthetic-opaque", "index" => 0}]

      url =
        DialogueWireServer.start(self(), fn body ->
          payload(Map.put(body, "model", "other/model"), details, streaming)
        end)

      config = config(unquote(provider), streaming, url)
      assert {:ok, response} = generate(config, request(), streaming)
      assert_receive {:encoded_request, first}
      assert first["model"] == "google/gemini-3.5-flash-lite"
      [call] = response.tool_calls
      assistant = Message.assistant(response.text, [call], response.provider_replay)

      continuation = %{
        request()
        | messages: [
            Message.user("Lookup"),
            assistant,
            Message.tool(call, %{"ok" => true}),
            Message.user("Continue")
          ]
      }

      assert {:ok, _} = generate(config, continuation, streaming)
      assert_receive {:encoded_request, body}
      assert body["model"] == "other/model"

      if unquote(provider) == "openrouter" do
        assert first["models"] == ["google/gemini-3.5-flash-lite", "other/model"]
        refute Map.has_key?(body, "models")
        refute Map.has_key?(body, "route")
      else
        assert first["provider"]["fallback"] == "alternate/model"
        assert body["provider"]["fallback"] == "false"
        refute Map.has_key?(body, "model_routing_config")
      end

      conflict = %{
        assistant
        | provider_replay: Map.put(assistant.provider_replay, "response_model", "third/model")
      }

      assert_raise ArgumentError, fn ->
        Provider.prepare_request(config, %{
          continuation
          | messages: continuation.messages ++ [conflict]
        })
      end
    end
  end

  defp config(provider, streaming, url) do
    {:ok, options} =
      Vxpipe.AgentRuntime.ProviderSelection.translate(
        provider,
        "google/gemini-3.5-flash-lite",
        %{},
        %{}
      )

    options =
      options
      |> Keyword.put(:api_key, "test-only")
      |> Keyword.put(:streaming, streaming)
      |> Keyword.update!(:generation_options, fn options ->
        routing =
          if provider == "openrouter",
            do: [
              openrouter_models: ["google/gemini-3.5-flash-lite", "other/model"],
              openrouter_route: "fallback"
            ],
            else: [
              provider: %{fallback: "alternate/model"},
              model_routing_config: %{available_models: ["other/model"]}
            ]

        options |> Keyword.put(:base_url, url) |> Keyword.put(:provider_options, routing)
      end)

    {:ok, config} = Provider.new(options)
    config
  end

  defp request do
    tool = %ModelTool{
      name: "lookup",
      description: "Lookup",
      input_schema: %{"type" => "object", "properties" => %{}}
    }

    %{
      ModelRequest.new([Message.user("Lookup")], [tool], [], %{})
      | reply_protocol: :mode_message_v1
    }
  end

  defp payload(body, details, streaming, field \\ :reasoning_details, extra \\ %{}) do
    call = %{id: "call-1", type: "function", function: %{name: "lookup", arguments: "{}"}}

    message =
      %{role: "assistant", content: "", tool_calls: [call]}
      |> Map.put(field, details)
      |> Map.merge(extra)

    payload = %{
      id: "response-1",
      model: body["model"],
      choices: [%{index: 0, message: message, finish_reason: "tool_calls"}]
    }

    if streaming do
      blocks = if is_list(details), do: Enum.map(details, &[&1]), else: [details]

      events =
        Enum.map(blocks, fn block ->
          %{
            payload
            | choices: [
                %{index: 0, delta: Map.merge(%{field => block}, extra), finish_reason: nil}
              ]
          }
        end)

      final = %{
        payload
        | choices: [
            %{
              index: 0,
              delta: %{role: "assistant", tool_calls: [Map.put(call, :index, 0)]},
              finish_reason: "tool_calls"
            }
          ]
      }

      {"text/event-stream",
       Enum.map_join(events ++ [final], "", &("data: " <> JSON.encode!(&1) <> "\n\n")) <>
         "data: [DONE]\n\n"}
    else
      {"application/json", JSON.encode!(payload)}
    end
  end

  defp generate(config, request, false), do: Provider.generate(config, request)
  defp generate(config, request, true), do: Provider.stream(config, request, fn _ -> :ok end)
end
