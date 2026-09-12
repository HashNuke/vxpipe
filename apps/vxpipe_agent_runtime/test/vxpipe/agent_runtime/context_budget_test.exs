defmodule Vxpipe.AgentRuntime.ContextBudgetTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ContextBudget,
    Message,
    ModelRequest,
    ModelTool,
    PendingInvocation,
    RequestBudget
  }

  test "reserves output before applying the 75 percent trigger and below-50 percent target" do
    assert {:ok, budget} =
             ContextBudget.new(context_window_tokens: 1_000, output_reserve_tokens: 200)

    assert budget.usable_input_tokens == 800
    assert budget.trigger_input_tokens == 600
    assert budget.target_input_tokens == 399

    assert {:ok, :within_budget} = ContextBudget.assess(budget, 599)
    assert {:ok, {:compact, 399}} = ContextBudget.assess(budget, 600)
    assert {:ok, {:compact, 399}} = ContextBudget.assess(budget, 900)
  end

  test "rounds the trigger upward and keeps the target strictly below half" do
    assert {:ok, budget} =
             ContextBudget.new(context_window_tokens: 103, output_reserve_tokens: 4)

    assert budget.usable_input_tokens == 99
    assert budget.trigger_input_tokens == 75
    assert budget.target_input_tokens == 49
  end

  test "rejects unusable windows and invalid measurements" do
    assert {:error, :invalid_context_budget} =
             ContextBudget.new(context_window_tokens: 100, output_reserve_tokens: 100)

    assert {:error, :invalid_context_budget} =
             ContextBudget.new(context_window_tokens: 100, output_reserve_tokens: 0)

    assert {:ok, budget} =
             ContextBudget.new(context_window_tokens: 100, output_reserve_tokens: 20)

    assert {:error, :invalid_input_token_count} = ContextBudget.assess(budget, -1)
  end

  test "measures the complete normalized request before deciding" do
    request = realistic_request()

    assert {:ok, budget} =
             ContextBudget.new(context_window_tokens: 1_000, output_reserve_tokens: 200)

    counter =
      {Vxpipe.AgentRuntime.TestInputTokenCounter, %{owner: self(), result: {:ok, 600}}}

    assert {:ok, %{decision: {:compact, 399}, input_tokens: 600}} =
             RequestBudget.assess(request, budget, counter)

    assert_receive {:input_tokens_counted, counter_pid, ^request}
    refute counter_pid == self()
  end

  test "normalizes counter failures without making a provider request" do
    request = realistic_request()

    assert {:ok, budget} =
             ContextBudget.new(context_window_tokens: 1_000, output_reserve_tokens: 200)

    counter =
      {Vxpipe.AgentRuntime.TestInputTokenCounter,
       %{owner: self(), result: {:error, :counter_failed}}}

    assert {:error, :input_token_count_unavailable} =
             RequestBudget.assess(request, budget, counter)
  end

  defp realistic_request do
    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: "tool_running",
        tool_name: "fetch_order",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_17"
      )

    tool = %ModelTool{
      name: "fetch_order",
      description: "Fetch an order by its public reference",
      input_schema: %{
        "type" => "object",
        "properties" => %{"reference" => %{"type" => "string"}},
        "required" => ["reference"]
      }
    }

    ModelRequest.new(
      [
        Message.system("Follow the configured call policy."),
        Message.user("Please check order 17."),
        Message.assistant("I am checking that now.", [])
      ],
      [tool],
      [pending],
      %{
        "call_variables" => %{
          "order" => %{"revision" => 3, "value" => %{"reference" => "order-17"}}
        }
      },
      %{activation_id: "activation_1", turn_id: "turn_18"}
    )
  end
end
