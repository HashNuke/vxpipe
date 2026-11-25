defmodule Vxpipe.AgentRuntime.PromptTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelContextCompactor, ModelResponse, Prompt}

  test "the pinned dialogue prompt requires raw JSON without Markdown fences" do
    assert {:ok, prompt} = Prompt.load(:llm_dialogue)
    assert prompt.text =~ "raw JSON"
    assert prompt.text =~ "code fences"
    assert prompt.text =~ "matching the participant envelope used in history"

    assert prompt.text =~
             ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Hello."})
  end

  test "shared instructions limit form collection and close a clearly out-of-scope call" do
    assert {:ok, prompt} = Prompt.load(:shared)
    assert prompt.text =~ "collection_schemas"
    assert prompt.text =~ "do not offer to collect"
    assert prompt.text =~ "business facts only from your instructions or an authorized knowledge tool"
    assert prompt.text =~ "invoke the supplied hangup tool in this turn"
    assert prompt.text =~ "put the caller-facing sentence in the announcement argument"
  end

  test "explicit built-in compactors pin the same source while custom callback state stays owned" do
    provider = Vxpipe.AgentRuntime.TestModelProvider
    model = %{mode: :scripted, test_owner: self()}
    options = [enabled: true, context_window_tokens: 1_000, output_reserve_tokens: 100]

    assert {:ok, config} =
             Vxpipe.AgentRuntime.CompactionConfiguration.new(
               provider,
               model,
               Keyword.put(
                 options,
                 :compactor,
                 {ModelContextCompactor, %{model_provider: provider, model: model}}
               )
             )

    assert {ModelContextCompactor, %{summary_prompt: %Prompt{} = prompt}} = config.compactor
    assert {:ok, ^prompt} = Prompt.load(:conversation_summary)

    custom = {Vxpipe.AgentRuntime.TestContextCompactor, %{marker: "custom-owned"}}

    assert {:ok, config} =
             Vxpipe.AgentRuntime.CompactionConfiguration.new(
               provider,
               model,
               Keyword.put(options, :compactor, custom)
             )

    assert config.compactor == custom

    invalid =
      {ModelContextCompactor, %{model_provider: provider, model: model, summary_prompt: :invalid}}

    assert {:error, :invalid_compaction_configuration} =
             Vxpipe.AgentRuntime.CompactionConfiguration.new(
               provider,
               model,
               Keyword.put(options, :compactor, invalid)
             )
  end

  test "packages bounded editable instruction sources with stable revisions" do
    for name <- [:shared, :llm_dialogue, :conversation_summary] do
      assert {:ok, prompt} = Prompt.load(name)
      assert prompt.name == name
      assert String.trim(prompt.text) != ""
      assert byte_size(prompt.revision) == 64
      assert {:ok, ^prompt} = Prompt.load(name)
      refute inspect(prompt) =~ prompt.text
    end

    assert {:error, :prompt_unavailable} = Prompt.load(:unknown)
  end

  test "pins compactor instructions and fails missing assets instead of silently replacing them" do
    directory =
      Path.join(System.tmp_dir!(), "vxpipe-prompt-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    model = %{mode: :scripted, test_owner: self()}

    assert {:error, :prompt_unavailable} =
             ModelContextCompactor.new(
               Vxpipe.AgentRuntime.TestModelProvider,
               model,
               prompt_directory: directory
             )

    source = Path.join(directory, "conversation-summary-system.md")
    File.write!(source, "Original instructions")

    assert {:ok, config} =
             ModelContextCompactor.new(
               Vxpipe.AgentRuntime.TestModelProvider,
               model,
               prompt_directory: directory
             )

    File.write!(source, "Later instructions")

    {:ok, request} =
      Vxpipe.AgentRuntime.CompactionRequest.new(
        [Vxpipe.AgentRuntime.Message.user("history")],
        30,
        %{},
        []
      )

    task = Task.async(fn -> ModelContextCompactor.compact(config, request) end)
    assert_receive {:model_provider_process, provider, captured}
    assert List.first(captured.messages).content == "Original instructions"
    {:ok, response} = ModelResponse.new(text: "summary")
    send(provider, {:test_model_response, {:ok, response}})
    assert {:ok, _} = Task.await(task)
    File.write!(source, String.duplicate("x", 65_537))
    assert {:error, :prompt_unavailable} = Prompt.load(:conversation_summary, directory)
  end
end
