defmodule Vxpipe.AgentRuntime.Provider.UniversalTerminalWireTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{DialogueWireServer, Event, Session, TestPendingContextSource}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider
  alias Vxpipe.Providers.{LiveModels, Registry}

  @providers ~w(google openai deepseek fireworks openrouter zenmux)
  @cases [
    {:speaker, ~s({"agent_mode":"speaker","message":"Hello."}), :completed},
    {:silence, ~s({"agent_mode":"listener","message":null}), :completed},
    {:cue, ~s({"agent_mode":"listener","message":"Go ahead."}), :completed},
    {:duplicate, ~s({"agent_mode":"speaker","message":"One","message":"Two"}), :failed},
    {:unknown_mode, ~s({"agent_mode":"other","message":"Hello."}), :failed},
    {:speaker_null, ~s({"agent_mode":"speaker","message":null}), :failed},
    {:malformed, "Not JSON", :failed},
    {:oversized, JSON.encode!(%{agent_mode: "speaker", message: String.duplicate("x", 512)}),
     :failed},
    {:refusal, ~s({"agent_mode":"speaker","message":"Hello."}), :failed},
    {:truncation, ~s({"agent_mode":"speaker","message":"Hello."}), :failed}
  ]

  test "the terminal wire matrix includes every installed LLM integration" do
    installed = for {id, capabilities} <- Registry.catalog(), :llm in capabilities, do: id
    assert Enum.sort(installed) == Enum.sort(@providers)
  end

  for provider <- @providers, streaming <- [false, true], {kind, text, status} <- @cases do
    @tag capture_log: true
    test "#{provider} streaming=#{streaming} enforces #{kind} at the Session boundary" do
      provider = unquote(provider)
      streaming = unquote(streaming)
      kind = unquote(kind)
      expected = unquote(status)
      selection = LiveModels.llm(provider)

      url =
        DialogueWireServer.start(self(), fn body ->
          response(provider, streaming, body, kind, unquote(text))
        end)

      {:ok, options} =
        Vxpipe.AgentRuntime.ProviderSelection.translate(
          provider,
          selection.model,
          %{},
          selection.specific
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
           maximum_output_bytes: 256,
           model_provider: Provider,
           model: config,
           pending_context_source: {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()}
        )

      assert {:ok, result} = Session.request(session, "Hello", %{})
      assert result.status == expected
      assert result.output == nil
      assert_reason(result, kind)
      assert_dialogue(result, kind)
      refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
      assert_receive {:encoded_request, _}
      refute_receive {:encoded_request, _}, 0
    end
  end

  defp assert_reason(result, kind) when kind in [:refusal, :truncation],
    do: assert(result.reason == :invalid_provider_response)

  defp assert_reason(result, :oversized), do: assert(result.reason == :output_too_large)

  defp assert_reason(result, kind)
       when kind in [:duplicate, :unknown_mode, :speaker_null, :malformed],
       do: assert(result.reason == :invalid_dialogue)

  defp assert_reason(_result, _kind), do: :ok

  defp assert_dialogue(%{dialogue: dialogue}, :speaker),
    do: assert(%{agent_mode: :speaker, message: "Hello."} = dialogue)

  defp assert_dialogue(%{dialogue: dialogue}, :silence),
    do: assert(%{agent_mode: :listener, message: nil} = dialogue)

  defp assert_dialogue(%{dialogue: dialogue}, :cue),
    do: assert(%{agent_mode: :listener, message: "Go ahead."} = dialogue)

  defp assert_dialogue(%{dialogue: dialogue}, _kind), do: assert(is_nil(dialogue))

  defp response("google", streaming, _body, kind, text) do
    finish =
      case kind do
        :refusal -> "SAFETY"
        :truncation -> "MAX_TOKENS"
        _ -> "STOP"
      end

    payload = %{
      candidates: [%{content: %{role: "model", parts: [%{text: text}]}, finishReason: finish}]
    }

    encode_chat(payload, streaming)
  end

  defp response("openai", streaming, body, kind, text) do
    content = [%{type: "output_text", text: text}]

    content =
      if kind == :refusal, do: content ++ [%{type: "refusal", refusal: "Declined"}], else: content

    payload = %{
      id: "resp_fixture",
      model: body["model"],
      status: if(kind == :truncation, do: "incomplete", else: "completed"),
      output: [
        %{
          type: "message",
          id: "msg_fixture",
          role: "assistant",
          status: "completed",
          content: content
        }
      ]
    }

    payload =
      if kind == :truncation,
        do: Map.put(payload, :incomplete_details, %{reason: "max_output_tokens"}),
        else: payload

    if streaming do
      terminal = if kind == :truncation, do: "response.incomplete", else: "response.completed"

      events = [
        %{
          type: "response.output_text.delta",
          delta: text,
          output_index: 0,
          content_index: 0,
          item_id: "msg_fixture"
        },
        %{type: terminal, response: payload}
      ]

      {"text/event-stream",
       Enum.map_join(events, &("event: " <> &1.type <> "\ndata: " <> JSON.encode!(&1) <> "\n\n"))}
    else
      {"application/json", JSON.encode!(payload)}
    end
  end

  defp response(_provider, streaming, body, kind, text) do
    message = %{role: "assistant", content: text}
    message = if kind == :refusal, do: Map.put(message, :refusal, "Declined"), else: message
    field = if streaming, do: :delta, else: :message

    payload = %{
      id: "chat_fixture",
      model: body["model"],
      choices: [
        %{
          field => message,
          :index => 0,
          :finish_reason => if(kind == :truncation, do: "length", else: "stop")
        }
      ]
    }

    encode_chat(payload, streaming)
  end

  defp encode_chat(payload, true),
    do: {"text/event-stream", "data: " <> JSON.encode!(payload) <> "\n\ndata: [DONE]\n\n"}

  defp encode_chat(payload, false), do: {"application/json", JSON.encode!(payload)}
end
