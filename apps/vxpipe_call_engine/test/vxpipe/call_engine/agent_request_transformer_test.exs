defmodule Vxpipe.CallEngine.AgentRequestTransformerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.State
  alias Vxpipe.CallEngine.AgentRequestTransformer
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture
  alias Vxpipe.CallEngine.TestVariableProjectionDispatcher

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

  test "keeps engine-origin continuations as provider-compatible input" do
    engine_observation = "background invocation tool-one completed"

    context =
      Context.new(system_prompt: "Stay concise.")
      |> Context.append_user("caller question", refs: %{vxpipe_request_id: "caller-request"})
      |> Context.append_assistant("I started it.")
      |> Context.append_user(engine_observation,
        refs: %{vxpipe_origin: :engine, vxpipe_request_id: "continuation-request"}
      )

    state =
      engine_observation
      |> State.new("Stay concise.", request_id: "continuation-request")
      |> then(&%{&1 | context: context})

    request = %{messages: Context.to_messages(context), llm_opts: [], tools: %{}, model: :fast}

    assert {:ok, %{messages: messages}} =
             AgentRequestTransformer.transform_request(request, state, %{}, %{})

    assert Enum.map(messages, &{&1.role, &1.content}) == [
             {:system, "Stay concise."},
             {:user, "caller question"},
             {:assistant, "I started it."},
             {:user, engine_observation}
           ]

    assert Enum.at(messages, -1).refs.vxpipe_origin == :engine
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

  test "inserts a refreshed Call Variables projection without adding it to history" do
    first = %{
      "global_revision" => 0,
      "sections" => %{
        "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
      }
    }

    dispatcher =
      start_supervised!({TestVariableProjectionDispatcher, projection: first})

    context =
      Context.new(system_prompt: "Stay concise.")
      |> Context.append_user("current user")

    state =
      "current user"
      |> State.new("Stay concise.", request_id: "variables-request")
      |> then(&%{&1 | context: context})

    request = %{messages: Context.to_messages(context), llm_opts: [], tools: %{}, model: :fast}

    assert {:ok, %{messages: first_messages}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{vxpipe_tool_dispatcher: dispatcher}
             )

    assert [
             %{role: :system, content: "Stay concise."},
             %{role: :system, content: first_projection},
             %{role: :user, content: "current user"}
           ] = first_messages

    assert first_projection =~ "Current Call Variables"
    assert first_projection =~ "order-1"

    second = %{
      "global_revision" => 1,
      "sections" => %{
        "order" => %{"revision" => 1, "value" => %{"id" => "order-2"}}
      }
    }

    assert :ok = TestVariableProjectionDispatcher.replace(dispatcher, second)

    assert {:ok, %{messages: second_messages}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{vxpipe_tool_dispatcher: dispatcher}
             )

    assert Enum.count(second_messages, fn message -> message.role == :system end) == 2
    assert Enum.any?(second_messages, &String.contains?(&1.content, "order-2"))
    refute Enum.any?(second_messages, &String.contains?(&1.content, "order-1"))
    assert Context.to_messages(context) == request.messages
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
