defmodule Vxpipe.AgentRuntime.LiveUniversalConversationTest do
  use ExUnit.Case, async: false

  test "the shared conversation harness covers every installed LLM integration" do
    installed =
      for {provider, capabilities} <- Vxpipe.Providers.Registry.catalog(),
          :llm in capabilities,
          do: provider

    covered = Enum.map(Vxpipe.AgentRuntime.LiveUniversalConversation.providers(), &elem(&1, 0))
    assert Enum.sort(covered) == Enum.sort(installed)
  end

  test "every planned live selection accepts the common output budget before HTTP" do
    for {provider, _tag} <- Vxpipe.AgentRuntime.LiveUniversalConversation.providers() do
      selection = Vxpipe.Providers.LiveModels.llm(provider)

      assert {:ok, _options} =
               Vxpipe.AgentRuntime.ProviderSelection.translate(
                 provider,
                 selection.model,
                 %{
                   "max_tokens" =>
                     Vxpipe.AgentRuntime.LiveUniversalConversation.maximum_output_tokens()
                 },
                 selection.specific
               )
    end
  end

  import ExUnit.CaptureIO
  alias Vxpipe.AgentRuntime.{DialogueWireServer, LiveUniversalConversation}

  @long "The Northstar office opens at 9 in the morning. It closes at 5 in the afternoon. These hours apply Monday through Friday."

  setup do
    key_env = Vxpipe.Providers.LiveModels.llm("google").env
    prior_key = System.get_env(key_env)
    System.put_env(key_env, "test-only")

    on_exit(fn ->
      if prior_key,
        do: System.put_env(key_env, prior_key),
        else: System.delete_env(key_env)
    end)

    :ok
  end

  for streaming <- [false, true] do
    @tag capture_log: true
    test "a valid full conversation passes with streaming=#{streaming}" do
      streaming = unquote(streaming)
      url = fixture(nil, nil, streaming)

      output =
        capture_io(fn ->
          assert :ok =
                   LiveUniversalConversation.run("google", streaming, :portable_json,
                     base_url: url
                   )
        end)

      rows = evidence(output)
      assert length(rows) == 10
      assert Enum.all?(rows, &(&1["semantic_outcome"] in ["passed", "not_applicable"]))
    end
  end

  for {step, bad} <- [
        {"long",
         "Our office opens at five and closes at nine Monday to Friday. Please visit during those hours. Our team is happy to help with your questions."},
        {"lookup", "The lookup has completed successfully and the reference is READY."},
        {"unrelated", "14"},
        {"completion", "NOT READY"},
        {"after_cancel", "NOT READY"}
      ] do
    @tag capture_log: true
    test "rejects false #{step} output and marks its semantic evidence failed" do
      step = unquote(step)
      url = fixture(step, unquote(bad))

      output =
        capture_io(fn ->
          assert_raise ExUnit.AssertionError, fn ->
            LiveUniversalConversation.run("google", false, :portable_json, base_url: url)
          end
        end)

      assert [%{"step" => ^step, "outcome" => "completed", "semantic_outcome" => "failed"}] =
               Enum.filter(evidence(output), &(&1["semantic_outcome"] == "failed"))
    end
  end

  defp fixture(bad_step, bad_text, streaming \\ false) do
    DialogueWireServer.start(self(), fn body ->
      last_part = body["contents"] |> List.last() |> Map.fetch!("parts") |> List.last()

      input =
        case Map.get(last_part, "text") do
          text when is_binary(text) ->
            case JSON.decode(text) do
              {:ok, %{"message" => message}} -> message
              {:ok, %{"event" => event}} -> event
              _ -> text
            end

          _ ->
            "tool-result"
        end

      part =
        cond do
          input == "tool-result" ->
            dialogue("lookup", "speaker", "The lookup is running.", bad_step, bad_text)

          String.contains?(input, "greet") ->
            dialogue("short", "speaker", "Hello.", bad_step, bad_text)

          String.contains?(input, "three sentences") ->
            dialogue("long", "speaker", @long, bad_step, bad_text)

          String.contains?(input, "wait silently") ->
            dialogue("silent", "listener", nil, bad_step, bad_text)

          String.contains?(input, "Go ahead") ->
            dialogue("cue", "listener", "Go ahead", bad_step, bad_text)

          String.contains?(input, "Call lookup") ->
            call = %{
              functionCall: %{name: "lookup", args: %{reference: "DEMO-42"}},
              thoughtSignature: "test"
            }

            if bad_step == "lookup" do
              [dialogue("lookup", "speaker", nil, bad_step, bad_text), call]
            else
              [call]
            end

          String.contains?(input, "two plus two") ->
            dialogue("unrelated", "speaker", "Four", bad_step, bad_text)

          String.contains?(input, "completed successfully") ->
            dialogue("completion", "speaker", "DEMO-42 is READY", bad_step, bad_text)

          input == "idle_timeout" ->
            dialogue("idle", "listener", nil, bad_step, bad_text)

          true ->
            dialogue("after_cancel", "speaker", "READY", bad_step, bad_text)
        end

      payload =
        JSON.encode!(%{
          candidates: [%{content: %{role: "model", parts: List.wrap(part)}, finishReason: "STOP"}]
        })

      if streaming,
        do: {"text/event-stream", "data: " <> payload <> "\n\n"},
        else: {"application/json", payload}
    end)
  end

  defp dialogue(step, mode, _text, step, bad),
    do: %{
      text:
        JSON.encode!(%{
          type: "participant_message",
          participant_id: "agent",
          agent_mode: mode,
          message: bad
        })
    }

  defp dialogue(_step, mode, text, _bad_step, _bad),
    do: %{
      text:
        JSON.encode!(%{
          type: "participant_message",
          participant_id: "agent",
          agent_mode: mode,
          message: text
        })
    }

  defp evidence(output) do
    for line <- String.split(output, "\n"),
        String.starts_with?(line, "UNIVERSAL_REPLY_EVIDENCE ") do
      line |> String.replace_prefix("UNIVERSAL_REPLY_EVIDENCE ", "") |> JSON.decode!()
    end
  end
end
