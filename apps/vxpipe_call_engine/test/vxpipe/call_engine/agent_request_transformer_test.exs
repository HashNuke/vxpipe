defmodule Vxpipe.CallEngine.AgentRequestTransformerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.State
  alias Vxpipe.CallEngine.AgentRequestTransformer

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

    assert {:ok, %{messages: messages}} =
             AgentRequestTransformer.transform_request(
               request,
               state,
               %{},
               %{vxpipe_discarded_agent_request_ids: ["old-request"]}
             )

    assert Enum.map(messages, &Map.get(&1, :content)) == ["Stay concise.", "current user"]
  end
end
