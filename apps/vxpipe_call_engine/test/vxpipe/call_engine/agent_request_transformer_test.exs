defmodule Vxpipe.CallEngine.AgentRequestTransformerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.State
  alias Vxpipe.CallEngine.AgentRequestTransformer
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture

  test "excludes discarded request entries from every model projection" do
    context =
      Context.new(system_prompt: "Stay concise.")
      |> Context.append_user("discarded user", refs: %{vxpipe_request_id: "old-request"})
      |> Context.append_assistant("discarded answer", nil, refs: %{request_id: "old-request"})
      |> Context.append_user("current user", refs: %{vxpipe_request_id: "current-request"})

    state =
      "current user"
      |> State.new("Stay concise.", request_id: "current-request")
      |> then(&%{&1 | context: context})

    request = %{messages: Context.to_messages(context), llm_opts: [], tools: %{}, model: :fast}

    assert {:ok, %{messages: messages, model: "google:configured-model"}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{
                 vxpipe_discarded_agent_request_ids: ["old-request"],
                 vxpipe_model: "google:configured-model"
               }
             )

    assert Enum.map(messages, &Map.get(&1, :content)) == ["Stay concise.", "current user"]
  end

  test "uses an armed local fixture without adding controls to the call input" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    assert :ok = ModelFixture.arm(fixture, :missing)

    context =
      Context.new(system_prompt: "Stay concise.")
      |> Context.append_user("exercise the fixture")

    state =
      "exercise the fixture"
      |> State.new("Stay concise.", request_id: "fixture-request")
      |> then(&%{&1 | context: context})

    request = %{messages: Context.to_messages(context), llm_opts: [], tools: %{}, model: :fast}

    assert {:ok, %{llm_opts: [jido_ai_react_script: script]}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{vxpipe_model_fixture: fixture}
             )

    assert script.user == "exercise the fixture"
    assert [%{type: :answer, text: ""}] = script.turns
    assert %{next_scenario: :success} = ModelFixture.status(fixture)
  end

  test "applies the configured delay before returning local model output" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil,
         default_scenario: :success,
         delay_ms: 20,
         response: "Delayed fixture response."}
      )

    assert :ok = ModelFixture.arm(fixture, :delay)

    context =
      Context.new(system_prompt: "Stay concise.")
      |> Context.append_user("delay this response")

    state =
      "delay this response"
      |> State.new("Stay concise.", request_id: "fixture-delay-request")
      |> then(&%{&1 | context: context})

    request = %{messages: Context.to_messages(context), llm_opts: [], tools: %{}, model: :fast}
    started_at = System.monotonic_time(:millisecond)

    assert {:ok, %{llm_opts: [jido_ai_react_script: script]}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{vxpipe_model_fixture: fixture}
             )

    assert System.monotonic_time(:millisecond) - started_at >= 20
    assert [%{type: :answer, text: "Delayed fixture response."}] = script.turns
  end
end
