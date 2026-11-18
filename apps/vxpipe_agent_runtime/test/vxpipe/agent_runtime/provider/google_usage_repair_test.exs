defmodule Vxpipe.AgentRuntime.Provider.GoogleUsageRepairTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Session, TestPendingContextSource}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @tag capture_log: true
  test "reported Google output usage allows the same bounded correction in both wire modes" do
    for streaming <- [false, true],
        strategy <- [:google_object, :portable_json],
        {usage, remaining} <- [
          {%{promptTokenCount: 20, candidatesTokenCount: 10, totalTokenCount: 30}, 90},
          {%{
             promptTokenCount: 20,
             candidatesTokenCount: 10,
             thoughtsTokenCount: 3,
             totalTokenCount: 33
           }, 87},
          {%{promptTokenCount: 20, candidatesTokenCount: 0, totalTokenCount: 20}, 100}
        ] do
      session = session(streaming, strategy, usage)

      assert {:ok, %{status: :completed, dialogue: %{agent_mode: :listener, message: nil}}} =
               Session.request(session, "Hello", %{}),
             inspect({streaming, strategy})

      assert_receive {:encoded_request, first}
      assert_receive {:encoded_request, second}
      assert first["generationConfig"]["maxOutputTokens"] == 100
      assert second["generationConfig"]["maxOutputTokens"] == remaining
      refute_receive {:encoded_request, _}
    end
  end

  @tag capture_log: true
  test "missing or inferred output counts do not authorize correction in either wire mode" do
    for streaming <- [false, true],
        strategy <- [:google_object, :portable_json],
        usage <- [
          nil,
          %{},
          %{thoughtsTokenCount: 10},
          %{promptTokenCount: 20, totalTokenCount: 30},
          %{candidatesTokenCount: 10, thoughtsTokenCount: "invalid"},
          %{candidatesTokenCount: -1}
        ] do
      session = session(streaming, strategy, usage)

      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} =
               Session.request(session, "Hello", %{})

      assert_receive {:encoded_request, _}
      refute_receive {:encoded_request, _}
    end
  end

  @tag capture_log: true
  test "only the final streamed usage snapshot authorizes correction" do
    known = %{promptTokenCount: 20, candidatesTokenCount: 10, totalTokenCount: 30}

    for strategy <- [:google_object, :portable_json],
        final <- [
          :omitted,
          %{},
          %{promptTokenCount: 20},
          %{candidatesTokenCount: "invalid"},
          %{candidatesTokenCount: 10, thoughtsTokenCount: "invalid"}
        ] do
      session = session(true, strategy, [known, final])

      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} =
               Session.request(session, "Hello", %{})

      assert_receive {:encoded_request, _}
      refute_receive {:encoded_request, _}
    end

    for strategy <- [:google_object, :portable_json],
        first <- [:omitted, %{promptTokenCount: 20}] do
      session = session(true, strategy, [first, known])
      assert {:ok, %{status: :completed}} = Session.request(session, "Hello", %{})
      assert_receive {:encoded_request, _}
      assert_receive {:encoded_request, second}
      assert second["generationConfig"]["maxOutputTokens"] == 90
      refute_receive {:encoded_request, _}
    end
  end

  @tag capture_log: true
  test "decreasing stream components cannot undercount a correction allowance" do
    first = %{promptTokenCount: 20, candidatesTokenCount: 10, thoughtsTokenCount: 7}

    for strategy <- [:google_object, :portable_json],
        final <- [
          %{candidatesTokenCount: 20},
          %{candidatesTokenCount: 20, thoughtsTokenCount: 3},
          %{candidatesTokenCount: 5, thoughtsTokenCount: 20}
        ] do
      session = session(true, strategy, [first, final])

      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} =
               Session.request(session, "Hello", %{})

      assert_receive {:encoded_request, _}
      refute_receive {:encoded_request, _}
    end

    for strategy <- [:google_object, :portable_json] do
      final = %{promptTokenCount: 20, candidatesTokenCount: 20, thoughtsTokenCount: 7}
      session = session(true, strategy, [first, final])
      assert {:ok, %{status: :completed}} = Session.request(session, "Hello", %{})
      assert_receive {:encoded_request, _}
      assert_receive {:encoded_request, second}
      assert second["generationConfig"]["maxOutputTokens"] == 73
      refute_receive {:encoded_request, _}
    end
  end

  defp session(streaming, strategy, usage) do
    url =
      DialogueWireServer.start(self(), fn body ->
        text =
          if JSON.encode!(body) =~ "malformed-usage",
            do: ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}),
            else: "malformed-usage"

        if streaming do
          snapshots = if is_list(usage), do: usage, else: [usage]

          wire =
            snapshots
            |> Enum.with_index()
            |> Enum.map_join(fn {snapshot, index} ->
              last? = index == length(snapshots) - 1
              payload = payload(if(last?, do: text, else: ""), snapshot, last?)
              "data: " <> JSON.encode!(payload) <> "\n\n"
            end)

          {"text/event-stream", wire}
        else
          {"application/json", JSON.encode!(payload(text, usage, true))}
        end
      end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: "google:gemini-3.5-flash-lite",
        streaming: streaming,
        generation_options: [base_url: url, max_tokens: 100]
      )

    config = %{config | reply_strategy: strategy}

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         history_mode: :host_settled,
         reply_protocol: :mode_message_v1,
         model_provider: Provider,
         model: config,
         pending_context_source: {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
         event_destination: self()},
        id: make_ref()
      )

    session
  end

  defp payload(text, usage, last?) do
    candidate = %{content: %{role: "model", parts: [%{text: text}]}}
    candidate = if last?, do: Map.put(candidate, :finishReason, "STOP"), else: candidate
    body = %{candidates: [candidate]}
    if usage == :omitted, do: body, else: Map.put(body, :usageMetadata, usage)
  end
end
