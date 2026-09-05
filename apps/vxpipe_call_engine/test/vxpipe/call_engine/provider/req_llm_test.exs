defmodule Vxpipe.CallEngine.Provider.ReqLLMTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Context
  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.Provider.ReqLLM, as: ReqLLMProvider

  test "resolves the configured model and translates the neutral request" do
    assert {:ok, config} =
             ReqLLMProvider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [temperature: 0.2, max_tokens: 256]
             )

    messages = [
      %Message{role: :system, content: "Be concise."},
      %Message{role: :user, content: "hello"},
      %Message{role: :assistant, content: "Hello."},
      %Message{role: :user, content: "What did I say?"}
    ]

    assert {model, context, options} = ReqLLMProvider.prepare_request(config, messages)
    assert model.provider == :google
    assert model.id == "gemini-3.5-flash-lite"
    assert Keyword.fetch!(options, :api_key) == "runtime-secret"
    assert Keyword.fetch!(options, :temperature) == 0.2
    assert Keyword.fetch!(options, :max_tokens) == 256
    refute ReqLLMProvider.streaming?(config)
    refute inspect(config) =~ "runtime-secret"

    assert context
           |> Context.to_list()
           |> Enum.map(&{&1.role, message_text(&1)}) ==
             [
               {:system, "Be concise."},
               {:user, "hello"},
               {:assistant, "Hello."},
               {:user, "What did I say?"}
             ]
  end

  test "allows streaming to be disabled for a buffered model" do
    assert {:ok, config} =
             ReqLLMProvider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               streaming: false
             )

    refute ReqLLMProvider.streaming?(config)
  end

  test "allows streaming to be enabled when deployment knowledge is newer than metadata" do
    assert {:ok, config} =
             ReqLLMProvider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               streaming: true
             )

    assert ReqLLMProvider.streaming?(config)
  end

  test "rejects missing credentials and credential overrides" do
    assert {:error, :invalid_configuration} =
             ReqLLMProvider.new(model: "google:gemini-3.5-flash-lite")

    assert {:error, :invalid_configuration} =
             ReqLLMProvider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [api_key: "override"]
             )
  end

  defp message_text(message) do
    Enum.map_join(message.content, "", & &1.text)
  end
end
