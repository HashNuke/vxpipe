defmodule Vxpipe.AgentRuntime.Provider.RouterNativeCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  for provider <- ["openrouter", "zenmux"],
      streaming <- [false, true],
      native_call? <- [false, true] do
    @tag capture_log: true
    test "reasoning cannot invent or overwrite native calls #{provider} #{streaming} native=#{native_call?}" do
      streaming = unquote(streaming)
      native_call? = unquote(native_call?)
      text = if native_call?, do: "", else: ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null})

      url =
        DialogueWireServer.start(self(), fn body ->
          call = %{
            id: "original-native-id",
            type: "function",
            function: %{name: "lookup", arguments: "{}"}
          }

          native = %{
            role: "assistant",
            content: "",
            reasoning:
              "Example only <｜tool▁call▁begin｜>different_tool<｜tool▁sep｜>{\"x\":1}<｜tool▁call▁end｜>",
            tool_calls: [call]
          }

          native = if native_call?, do: native, else: %{native | content: text, tool_calls: []}

          native = index_calls(native, streaming)

          choice =
            Map.put(
              %{index: 0, finish_reason: if(native_call?, do: "tool_calls", else: "stop")},
              if(streaming, do: :delta, else: :message),
              native
            )

          value = %{id: "response-1", model: body["model"], choices: [choice]}

          if streaming do
            {"text/event-stream", "data: " <> JSON.encode!(value) <> "\n\ndata: [DONE]\n\n"}
          else
            {"application/json", JSON.encode!(value)}
          end
        end)

      config = config(unquote(provider), streaming, url)
      assert {:ok, response} = generate(config, request(), streaming)

      if native_call? do
        assert [%{id: "original-native-id", name: "lookup", arguments: %{}}] = response.tool_calls
      else
        assert response.tool_calls == []
      end

      assert response.text == text
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

  defp generate(config, request, false), do: Provider.generate(config, request)
  defp generate(config, request, true), do: Provider.stream(config, request, fn _ -> :ok end)

  defp index_calls(native, false), do: native

  defp index_calls(native, true) do
    Map.update!(native, :tool_calls, fn calls ->
      calls |> Enum.with_index() |> Enum.map(fn {call, index} -> Map.put(call, :index, index) end)
    end)
  end
end
