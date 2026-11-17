defmodule Vxpipe.AgentRuntime.ProviderReplayTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    CompactionProjection,
    ConservativeInputTokenCounter,
    Message,
    ModelRequest,
    ModelResponse,
    SessionConfiguration
  }

  test "bounded replay data stays private and contributes to the model input budget" do
    replay = %{"format" => "test_v1", "opaque" => String.duplicate("opaque", 200)}
    assert {:ok, response} = ModelResponse.new(text: "reply", provider_replay: replay)
    assert ModelResponse.valid?(response)
    refute inspect(response) =~ "opaque"

    message = Message.assistant("reply", [], replay)
    assert message.provider_replay == replay
    refute inspect(message) =~ "opaque"
    baseline = ModelRequest.new([Message.assistant("reply", [])], [], [], %{})
    request = ModelRequest.new([message], [], [], %{})
    assert {:ok, ordinary} = ConservativeInputTokenCounter.count(nil, baseline)
    assert {:ok, with_replay} = ConservativeInputTokenCounter.count(nil, request)
    assert with_replay >= ordinary + byte_size(JSON.encode!(replay))

    projection = CompactionProjection.messages([message], "Summarize actual facts")
    refute List.last(projection).content =~ "opaque"
    assert List.last(projection).content =~ "reply"
  end

  test "malformed or oversized replay is rejected without truncation" do
    for replay <- [
          nil,
          [],
          %{"opaque" => self()},
          %{"opaque" => fn -> :ok end},
          %{atom_key: "value"}
        ] do
      assert {:error, :invalid_provider_replay} =
               ModelResponse.new(text: "reply", provider_replay: replay)
    end

    replay = %{"opaque" => String.duplicate("x", 65_536)}

    assert {:error, :provider_replay_too_large} =
             ModelResponse.new(text: "reply", provider_replay: replay)

    assert_raise ArgumentError, fn -> Message.assistant("reply", [], replay) end
  end

  test "provider replay cannot be injected through spoken or initial history" do
    {:ok, spoken} = Message.spoken_assistant("assistant", "Heard words", :speaker)
    forged = Map.put(spoken, :provider_replay, %{"opaque" => "not speech"})
    refute Message.valid_spoken?(forged, 1_024)

    options = [
      instructions: "policy",
      initial_messages: [forged],
      model_provider: Vxpipe.AgentRuntime.TestModelProvider,
      model: %{reply: "unused", test_owner: self()},
      event_destination: self()
    ]

    assert {:error, :invalid_configuration} = SessionConfiguration.new(options)

    caller = %{Message.user("hello") | provider_replay: %{"opaque" => "not speech"}}

    assert {:error, :invalid_configuration} =
             SessionConfiguration.new(Keyword.put(options, :initial_messages, [caller]))
  end
end
