defmodule Vxpipe.AgentRuntime.Integration.OpenAIDialogueProfileTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Dialogue, Input, Message, ModelRequest, ModelTool, Protocol}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @moduletag :live_providers
  @moduletag :live_openai
  @moduletag timeout: 180_000

  test "selected Responses profile retains strict schema, native tools and append-only input" do
    {:ok, selection} =
      Vxpipe.AgentRuntime.ProviderSelection.translate("openai", "gpt-6-luna", %{}, %{})

    {:ok, config} =
      Provider.new(Keyword.put(selection, :api_key, System.fetch_env!("OPENAI_API_KEY")))

    {:ok, snapshot} = Protocol.capture()

    {:ok, instructions} =
      Protocol.instructions(
        snapshot,
        "Read the latest participant message. Every requested spoken reply is a main response with agent_mode speaker, including the acknowledgment after a tool submission. SHORT: say Ready. LONG: say one sentence of about sixty words about a garden. QUIET: return listener with null. Only for LOOKUP call candidate_lookup once, then say Checking. MATH: say Four without tools. On the actual completion report the literal returned value. Do not repeat a pending tool.",
        :llm
      )

    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, [:finch, :request, :start], &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    tool = %ModelTool{
      name: "candidate_lookup",
      description: "Get a test value.",
      input_schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
    }

    history =
      Enum.reduce(["SHORT", "LONG", "QUIET"], [Message.system(instructions)], fn label, history ->
        messages = history ++ [input(label)]
        {response, dialogue} = dialogue(config, messages, tool, label)
        assert response.tool_calls == []

        if label == "QUIET" do
          assert dialogue.agent_mode == :listener
          assert dialogue.message == nil
          messages
        else
          assert dialogue.agent_mode == :speaker
          {:ok, spoken} = Message.spoken_assistant("assistant-live", dialogue.message, :speaker)
          messages ++ [spoken]
        end
      end)

    requested = history ++ [input("LOOKUP")]
    assert {:ok, %{tool_calls: [call]} = response} = candidate(config, requested, tool)
    assert call.name == tool.name
    assert call.arguments == %{}

    native =
      requested ++
        [
          Message.assistant(response.text, [call], response.provider_replay),
          Message.tool(call, %{"invocation_id" => call.id, "status" => "running"})
        ]

    {_ack, reply} = dialogue(config, native, tool, "TOOL_ACK")
    assert reply.agent_mode == :speaker
    {:ok, spoken} = Message.spoken_assistant("assistant-live", reply.message, :speaker)
    unrelated = native ++ [spoken, input("MATH")]
    {_math, reply} = dialogue(config, unrelated, tool, "MATH")
    assert reply.message =~ "Four" or reply.message =~ "4"
    {:ok, spoken} = Message.spoken_assistant("assistant-live", reply.message, :speaker)

    completed =
      unrelated ++
        [
          spoken,
          Message.user(
            "The worker completed candidate_lookup successfully with value vxpipe. Report the actual value.",
            :engine
          )
        ]

    {_completion, reply} = dialogue(config, completed, tool, "TOOL_COMPLETION")
    assert reply.message =~ "vxpipe"
    {:ok, spoken} = Message.spoken_assistant("assistant-live", reply.message, :speaker)
    {_later, reply} = dialogue(config, completed ++ [spoken, input("SHORT")], tool, "LATER")
    assert reply.message =~ "Ready"

    bodies =
      for _ <- 1..8 do
        assert_receive {:verified_wire, body}
        body
      end

    for [before, after_append] <- Enum.chunk_every(bodies, 2, 1, :discard) do
      assert Map.delete(before, "input") == Map.delete(after_append, "input")
      assert Enum.take(after_append["input"], length(before["input"])) == before["input"]
    end
  end

  def capture(_event, _measurements, %{request: %{host: "api.openai.com", body: body}}, owner),
    do: send(owner, {:candidate_request, body |> IO.iodata_to_binary() |> JSON.decode!()})

  def capture(_event, _measurements, _metadata, _owner), do: :ok

  defp input(text) do
    {:ok, input} = Input.participant("human-live", text, :listener)
    Message.user(Input.encode(input))
  end

  defp dialogue(config, messages, tool, label) do
    started = System.monotonic_time(:microsecond)
    assert {:ok, response} = candidate(config, messages, tool)
    assert response.tool_calls == []
    assert {:ok, dialogue} = Dialogue.decode(response.text), "#{label}: #{inspect(response.text)}"

    IO.puts(
      "openai_candidate_measurement " <>
        JSON.encode!(%{
          case: label,
          complete_validation_ms: (System.monotonic_time(:microsecond) - started) / 1_000,
          usage: response.usage
        })
    )

    {response, dialogue}
  end

  defp candidate(config, messages, tool) do
    request = %{ModelRequest.new(messages, [tool], [], %{}) | reply_protocol: :mode_message_v1}

    with {:ok, response} <- Provider.stream(config, request, fn _text -> :ok end) do
      assert_receive {:candidate_request, body}, 1_000
      schema = get_in(body, ["text", "format"]) || body["response_format"]
      assert schema["type"] == "json_schema"
      assert schema["strict"] == true
      assert schema["schema"] == Dialogue.schema()
      assert Enum.map(body["tools"], & &1["name"]) == ["candidate_lookup"]
      send(self(), {:verified_wire, body})

      expected_replay =
        Enum.flat_map(messages, fn message ->
          Enum.map(
            Map.get(message.provider_replay, "reasoning_items", []),
            &Map.put(&1, "type", "reasoning")
          )
        end)

      actual_replay = Enum.filter(body["input"], &(&1["type"] == "reasoning"))
      assert actual_replay == expected_replay

      IO.puts(
        "openai_candidate_replay " <>
          JSON.encode!(%{
            returned_reasoning_items:
              length(Map.get(response.provider_replay, "reasoning_items", [])),
            replayed_reasoning_items: length(actual_replay),
            replay_digest:
              :crypto.hash(:sha256, :erlang.term_to_binary(actual_replay, [:deterministic]))
              |> Base.encode16(case: :lower)
          })
      )

      {:ok, response}
    end
  end
end
