defmodule Vxpipe.Providers.OpenAI.GPTLiveDelegationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.OpenAI.GPTLiveDelegation

  test "deduplicates call IDs and continues once after a completed response" do
    {:ok, state} = GPTLiveDelegation.created(GPTLiveDelegation.new(), "d1", "responses", "r1")
    item = function_event("c1")

    assert {:ok, state, [{:tool_call, call_ref, "echo", %{"value" => 1}}]} =
             GPTLiveDelegation.event(state, "d1", item)

    assert {:ok, ^state, []} = GPTLiveDelegation.event(state, "d1", item)

    assert {:ok, state, []} =
             GPTLiveDelegation.event(state, "d1", %{"type" => "response.completed"})

    assert {:ok, state, "c1", [:continue]} = GPTLiveDelegation.result(state, call_ref)
    assert {:error, :stale_request} = GPTLiveDelegation.result(state, call_ref)
  end

  test "failed and incomplete responses retire calls and ignore late items" do
    for terminal <- ["response.failed", "response.incomplete"] do
      {:ok, state} = GPTLiveDelegation.created(GPTLiveDelegation.new(), "d1", "responses", "r1")

      {:ok, state, [{:tool_call, call_ref, _, _}]} =
        GPTLiveDelegation.event(state, "d1", function_event("c1"))

      assert {:ok, state, []} = GPTLiveDelegation.event(state, "d1", %{"type" => terminal})
      assert {:error, :stale_request} = GPTLiveDelegation.result(state, call_ref)
      assert {:ok, ^state, []} = GPTLiveDelegation.event(state, "d1", function_event("late"))
    end
  end

  defp function_event(call_id) do
    %{
      "type" => "response.output_item.done",
      "item" => %{
        "type" => "function_call",
        "call_id" => call_id,
        "name" => "echo",
        "arguments" => ~s({"value":1})
      }
    }
  end
end
