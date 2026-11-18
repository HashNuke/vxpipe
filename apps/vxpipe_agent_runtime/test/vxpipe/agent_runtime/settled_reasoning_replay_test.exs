defmodule Vxpipe.AgentRuntime.SettledReasoningReplayTest do
  use ExUnit.Case, async: false
  alias Vxpipe.AgentRuntime.{DialogueWireServer, Input, Message, Session, ToolDescriptor}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  for {provider, id} <- [
        {"deepseek", "deepseek-flash"},
        {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"}
      ],
      streaming <- [false, true],
      delivery <- [:full, :partial, :edited, :changed_mode, :none] do
    @tag capture_log: true
    test "unsigned final reasoning #{provider} #{streaming} #{delivery}" do
      delivery = unquote(delivery)
      provider = unquote(provider)
      streaming = unquote(streaming)
      url = DialogueWireServer.start(self(), &payload(&1, provider, streaming))

      {:ok, options} =
        Vxpipe.AgentRuntime.ProviderSelection.translate(provider, unquote(id), %{}, %{})

      options =
        options
        |> Keyword.put(:api_key, "test-only")
        |> Keyword.put(:streaming, streaming)
        |> Keyword.update!(:generation_options, &Keyword.put(&1, :base_url, url))

      {:ok, config} = Provider.new(options)

      {:ok, tool} =
        ToolDescriptor.new(
          name: "lookup",
          description: "Lookup",
          input_schema: %{"type" => "object", "properties" => %{}},
          binding: %{
            test_owner: self(),
            identity: :lookup,
            submission: {:accepted, :non_blocking}
          }
        )

      session =
        start_supervised!(
          {Session,
           instructions: "Be concise",
           history_mode: :host_settled,
           reply_protocol: :mode_message_v1,
           model_provider: Provider,
           model: config,
           tools: [tool],
           executor: Vxpipe.AgentRuntime.TestExecutor,
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()}
        )

      {:ok, input} = Input.participant("human", "Hello", :listener)
      first = %{request_id: "first"}

      assert {:ok, %{status: :completed, dialogue: %{message: "Hello."}}} =
               Session.request(session, input, first)

      assert_receive {:encoded_request, initial}
      assert initial["tools"] != []
      spoken = settled_message(delivery)
      assert :ok = Session.settle_output(session, first, spoken)
      assert {:ok, %{status: :completed}} = Session.request(session, input, %{request_id: "next"})
      assert_receive {:encoded_request, next}
      assistant = Enum.find(next["messages"], &(&1["role"] == "assistant"))

      assert_delivery(delivery, assistant, next)
    end
  end

  defp settled_message(:none), do: nil

  defp settled_message(delivery) do
    {text, mode} =
      case delivery do
        :full -> {"Hello.", :speaker}
        :partial -> {"Hel", :speaker}
        :edited -> {"Goodbye", :speaker}
        :changed_mode -> {"Hello.", :listener}
      end

    {:ok, message} = Message.spoken_assistant("agent", text, mode)
    message
  end

  defp assert_delivery(:full, assistant, _request) do
    assert assistant != nil
    assert JSON.decode!(assistant["content"])["message"] == "Hello."
    assert assistant["reasoning_content"] == "Private reasoning"
  end

  defp assert_delivery(_delivery, assistant, request) do
    assert is_nil(assistant) or assistant["reasoning_content"] in [nil, ""]
    refute JSON.encode!(request) =~ "Private reasoning"
  end

  defp payload(body, _provider, streaming) do
    message = %{role: "assistant", content: ~s({"agent_mode":"speaker","message":"Hello."})}

    message = Map.put(message, :reasoning_content, "Private reasoning")

    choice =
      Map.put(
        %{index: 0, finish_reason: "stop"},
        if(streaming, do: :delta, else: :message),
        message
      )

    payload = %{id: "response", model: body["model"], choices: [choice]}

    if streaming,
      do: {"text/event-stream", "data: " <> JSON.encode!(payload) <> "\n\ndata: [DONE]\n\n"},
      else: {"application/json", JSON.encode!(payload)}
  end
end
