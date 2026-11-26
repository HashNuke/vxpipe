defmodule Vxpipe.AgentRuntime.Provider.DialogueRepairWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Session, TestPendingContextSource}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  setup context do
    :ok = Req.Test.set_req_test_to_shared(context)
    :ok
  end

  test "zero-filled or partial Google usage does not grant an unmeasured repair allowance" do
    owner = self()

    for {usage, index} <- Enum.with_index([%{}, %{"thoughtsTokenCount" => 10}]) do
      Req.Test.stub(__MODULE__, fn connection ->
        send(owner, :wire_attempt)

        Req.Test.json(connection, %{
          candidates: [
            %{content: %{role: "model", parts: [%{text: "malformed"}]}, finishReason: "STOP"}
          ],
          usageMetadata: usage
        })
      end)

      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: "google:gemini-3.5-flash-lite",
          streaming: false,
          generation_options: [max_tokens: 100, req_http_options: [plug: {Req.Test, __MODULE__}]]
        )

      session =
        start_supervised!(
          {Session,
           [
             instructions: "Be concise",
             history_mode: :host_settled,
             reply_protocol: :mode_message_v1,
             model_provider: Provider,
             model: config,
             pending_context_source:
               {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
             event_destination: self()
           ]},
          id: index
        )

      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} =
               Session.request(session, "Hello", %{})

      assert_received :wire_attempt
      refute_received :wire_attempt
    end
  end

  test "real OpenAI response usage bounds the second HTTP attempt" do
    owner = self()

    Req.Test.stub(__MODULE__, fn connection ->
      body = connection |> Req.Test.raw_body() |> JSON.decode!()
      send(owner, {:wire_body, body})

      text =
        if JSON.encode!(body) =~ "malformed-wire",
          do:
            ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null}),
          else: "malformed-wire"

      Req.Test.json(connection, %{
        id: "r",
        model: "gpt-6-luna",
        status: "completed",
        usage: %{input_tokens: 20, output_tokens: 10, total_tokens: 30},
        output: [
          %{
            type: "message",
            id: "m",
            role: "assistant",
            status: "completed",
            content: [%{type: "output_text", text: text}]
          }
        ]
      })
    end)

    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")
    model = %{model | limits: %{context: 20_000}}

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: model,
        streaming: false,
        generation_options: [
          max_output_tokens: 100,
          req_http_options: [plug: {Req.Test, __MODULE__}]
        ]
      )

    session = start_supervised!({Session, options(config)})

    assert {:ok, %{status: :completed, dialogue: %{agent_mode: :listener, message: nil}}} =
             Session.request(session, "Hello", %{})

    assert_received {:wire_body, first}
    assert_received {:wire_body, second}
    assert first["max_output_tokens"] == 100
    assert second["max_output_tokens"] == 90
    refute_received {:wire_body, _}
  end

  test "ordinary Google Session tool rounds retain declarations and exact native results" do
    alias Vxpipe.AgentRuntime.ToolDescriptor
    owner = self()

    Req.Test.stub(__MODULE__, fn connection ->
      body = connection |> Req.Test.raw_body() |> JSON.decode!()
      send(owner, {:google_wire, body})

      parts =
        if JSON.encode!(body) =~ "functionResponse",
          do: [
            %{
              text:
                ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Checking."})
            }
          ],
          else: [
            %{
              functionCall: %{name: "lookup", args: %{}},
              thoughtSignature: "opaque-test-signature"
            }
          ]

      Req.Test.json(connection, %{
        candidates: [%{content: %{role: "model", parts: parts}, finishReason: "STOP"}]
      })
    end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: "google:gemini-3.5-flash-lite",
        streaming: false,
        generation_options: [req_http_options: [plug: {Req.Test, __MODULE__}]]
      )

    {:ok, tool} =
      ToolDescriptor.new(
        name: "lookup",
        description: "Lookup",
        input_schema: %{"type" => "object"},
        binding: %{test_owner: self(), identity: :lookup, submission: {:accepted, :blocking}}
      )

    session =
      start_supervised!(
        {Session, options(config) ++ [tools: [tool], executor: Vxpipe.AgentRuntime.TestExecutor]}
      )

    assert {:ok, %{status: :completed, dialogue: %{message: nil}}} =
             Session.request(session, "Lookup", %{})

    assert :ok = Session.settle_output(session, %{}, nil)

    assert {:ok, %{status: :completed, dialogue: %{message: "Checking."}}} =
             Session.continue_tool_result(session, "Lookup complete", %{id: "result"}, 2000)

    assert_received {:tool_submitted, _, :lookup, %{}, %{}, call_id}
    assert_received {:google_wire, first}
    assert_received {:google_wire, second}
    assert first["tools"] == second["tools"]
    assert JSON.encode!(first["tools"]) =~ "lookup"
    assert JSON.encode!(second["contents"]) =~ "opaque-test-signature"
    assert JSON.encode!(second["contents"]) =~ call_id
    refute_received {:tool_submitted, _, _, _, _, _}
  end

  test "runtime output cap wins over flat and namespaced native token options" do
    alias Vxpipe.AgentRuntime.{Message, ModelRequest}
    owner = self()

    Req.Test.stub(__MODULE__, fn connection ->
      send(owner, {:capped_wire, connection |> Req.Test.raw_body() |> JSON.decode!()})

      Req.Test.json(connection, %{
        id: "r",
        model: "gpt-6-luna",
        status: "completed",
        output: [
          %{
            type: "message",
            id: "m",
            role: "assistant",
            status: "completed",
            content: [
              %{
                type: "output_text",
                text:
                  ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null})
              }
            ]
          }
        ]
      })
    end)

    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")

    for native <- [[max_output_tokens: 100], [openai: [max_output_tokens: 100]]] do
      {:ok, config} =
        Provider.new(
          api_key: "test-only",
          model: model,
          streaming: false,
          generation_options: [
            provider_options: native,
            req_http_options: [plug: {Req.Test, __MODULE__}]
          ]
        )

      assert config.maximum_output_tokens == 100

      request = %{
        ModelRequest.new([Message.user("Hello")], [], [], %{})
        | reply_protocol: :mode_message_v1,
          maximum_output_tokens: 37
      }

      assert {:ok, _} = Provider.generate(config, request)
      assert_received {:capped_wire, body}
      assert body["max_output_tokens"] == 37
    end
  end

  defp options(config) do
    [
      instructions: "Be concise",
      history_mode: :host_settled,
      reply_protocol: :mode_message_v1,
      model_provider: Provider,
      model: config,
      pending_context_source: {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
      event_destination: self()
    ]
  end
end
