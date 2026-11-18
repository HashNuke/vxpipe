defmodule Vxpipe.AgentRuntime.Provider.ChatUsageRepairTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Session, TestPendingContextSource}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  for {provider, model} <- [
        {"deepseek", "deepseek-flash"},
        {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"},
        {"openrouter", "google/gemini-3.5-flash-lite"},
        {"zenmux", "google/gemini-3.5-flash-lite"}
      ],
      streaming <- [false, true],
      {kind, usage, remaining} <- [
        {:reported, %{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30}, 90},
        {:reported_zero, %{prompt_tokens: 20, completion_tokens: 0, total_tokens: 20}, 100},
        {:output_only, %{completion_tokens: 10}, 90},
        {:invalid_reasoning,
         %{completion_tokens: 10, completion_tokens_details: %{reasoning_tokens: "invalid"}},
         nil},
        {:invalid_details, %{completion_tokens: 10, completion_tokens_details: "invalid"}, nil},
        {:omitted, nil, nil},
        {:empty, %{}, nil},
        {:input_only, %{prompt_tokens: 20, total_tokens: 30}, nil},
        {:reasoning_only, %{completion_tokens_details: %{reasoning_tokens: 10}}, nil},
        {:negative, %{prompt_tokens: 20, completion_tokens: -1}, nil},
        {:invalid, %{prompt_tokens: 20, completion_tokens: "invalid"}, nil},
        {:wire_internal_aliases,
         %{input_tokens: 20, output_tokens: 10, usage_reported: %{output: true}}, nil}
      ] do
    @tag capture_log: true, usage_kind: kind, streaming: streaming, provider: provider
    test "#{provider} #{kind} streaming=#{streaming} respects raw usage when correcting dialogue" do
      streaming = unquote(streaming)
      usage = unquote(Macro.escape(usage))
      remaining = unquote(remaining)

      url =
        DialogueWireServer.start(self(), fn body ->
          text =
            if JSON.encode!(body) =~ "invalid-usage-fixture",
              do: ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}),
              else:
                ~s({"agent_mode":"speaker","message":"invalid-usage-fixture","participant_id":"agent","type":"invalid_usage_fixture"})

          field = if streaming, do: :delta, else: :message

          payload = %{
            id: "usage-response",
            model: body["model"],
            choices: [
              %{field => %{role: "assistant", content: text}, index: 0, finish_reason: "stop"}
            ]
          }

          payload = put_usage(payload, usage)

          if streaming,
            do:
              {"text/event-stream", "data: " <> JSON.encode!(payload) <> "\n\ndata: [DONE]\n\n"},
            else: {"application/json", JSON.encode!(payload)}
        end)

      {:ok, options} =
        Vxpipe.AgentRuntime.ProviderSelection.translate(
          unquote(provider),
          unquote(model),
          %{},
          %{}
        )

      options =
        options
        |> Keyword.put(:api_key, "test-only")
        |> Keyword.put(:streaming, streaming)
        |> Keyword.update!(:generation_options, fn options ->
          options |> Keyword.put(:base_url, url) |> Keyword.put(:max_tokens, 100)
        end)

      # Pin a known test context budget; Zenmux's catalog entry has no context limit.
      {:ok, model} = ReqLLM.model(Keyword.fetch!(options, :model))
      model = %{model | limits: Map.put(model.limits || %{}, :context, 20_000)}
      assert {:ok, config} = Provider.new(Keyword.put(options, :model, model))
      assert config.maximum_output_tokens == 100
      assert config.context_window_tokens == 20_000

      session =
        start_supervised!(
          {Session,
           instructions: "Be concise",
           history_mode: :host_settled,
           reply_protocol: :mode_message_v1,
           model_provider: Provider,
           model: config,
           pending_context_source: {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()}
        )

      result = Session.request(session, "Hello", %{})

      assert_receive {:agent_runtime_event,
                      %Vxpipe.AgentRuntime.Event{kind: :model_usage, data: _data}}

      if remaining do
        assert {:ok, %{status: :completed, dialogue: %{agent_mode: :listener, message: nil}}} =
                 result

        assert_receive {:encoded_request, first}
        assert_receive {:encoded_request, second}
        assert (first["max_tokens"] || first["max_completion_tokens"]) == 100
        assert (second["max_tokens"] || second["max_completion_tokens"]) == remaining
      else
        assert {:ok, %{status: :failed, reason: :invalid_dialogue}} = result
        assert_receive {:encoded_request, first}
        assert (first["max_tokens"] || first["max_completion_tokens"]) == 100
      end

      refute_receive {:encoded_request, _}, 0
    end
  end

  defp put_usage(payload, nil), do: payload
  defp put_usage(payload, usage), do: Map.put(payload, :usage, usage)
end
