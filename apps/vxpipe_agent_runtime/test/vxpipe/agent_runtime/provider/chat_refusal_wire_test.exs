defmodule Vxpipe.AgentRuntime.Provider.ChatRefusalWireTest do
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
      outcome <- [:refusal, :length, :absent, :null, :empty] do
    @tag capture_log: true
    test "#{provider} streaming=#{streaming} honors wire #{outcome} alongside valid dialogue" do
      streaming = unquote(streaming)
      outcome = unquote(outcome)

      url = DialogueWireServer.start(self(), &response(&1, streaming, outcome))

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
        |> Keyword.update!(:generation_options, &Keyword.put(&1, :base_url, url))

      {:ok, config} = Provider.new(options)

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

      assert_outcome(Session.request(session, "Hello", %{}), outcome)
      assert_receive {:encoded_request, _}
      refute_receive {:encoded_request, _}, 0
    end
  end

  defp assert_outcome(result, outcome) when outcome in [:refusal, :length] do
    assert {:ok, %{status: :failed, dialogue: nil}} = result
  end

  defp assert_outcome(result, _outcome) do
    assert {:ok, %{status: :completed, dialogue: %{message: "Hello."}}} = result
  end

  defp response(body, streaming, outcome) do
    message = %{role: "assistant", content: ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Hello."})}

    marker =
      case outcome do
        :refusal -> %{refusal: "Provider refused"}
        :null -> %{refusal: nil}
        :empty -> %{refusal: ""}
        _ -> %{}
      end

    finish = if outcome == :length, do: "length", else: "stop"
    base = %{id: "refusal-fixture", model: body["model"]}

    if streaming do
      # A marker-only chunk must survive a later valid text and stop chunk.
      first = Map.put(base, :choices, [%{index: 0, delta: marker, finish_reason: nil}])
      last = Map.put(base, :choices, [%{index: 0, delta: message, finish_reason: finish}])

      {"text/event-stream",
       Enum.map_join([first, last], &("data: " <> JSON.encode!(&1) <> "\n\n")) <>
         "data: [DONE]\n\n"}
    else
      payload =
        Map.put(base, :choices, [
          %{index: 0, message: Map.merge(message, marker), finish_reason: finish}
        ])

      {"application/json", JSON.encode!(payload)}
    end
  end
end
