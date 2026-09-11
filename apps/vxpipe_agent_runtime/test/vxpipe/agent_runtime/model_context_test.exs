defmodule Vxpipe.AgentRuntime.ModelContextTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ModelContext

  test "accepts a bounded JSON context and treats an absent source as empty" do
    context = %{
      "call_variables" => %{
        "order" => %{"revision" => 2, "value" => %{"id" => "order-17"}}
      }
    }

    assert {:ok, ^context} = fetch({:ok, context}, maximum_bytes: 256)
    assert {:ok, %{}} = ModelContext.fetch(nil, %{})
  end

  test "rejects non-JSON, reserved, and oversized projections" do
    assert {:error, :invalid_model_context} = fetch({:ok, %{private: "not-json-shaped"}})

    assert {:error, :invalid_model_context} =
             fetch({:ok, %{"pending_tool_invocations" => []}})

    assert {:error, :invalid_model_context} = fetch({:ok, ["not", "an", "object"]})

    assert {:error, :model_context_too_large} =
             fetch({:ok, %{"value" => String.duplicate("x", 64)}}, maximum_bytes: 16)
  end

  test "enforces the source timeout and terminates the stalled source call" do
    test_owner = self()

    fetch_task =
      Task.async(fn ->
        ModelContext.fetch(
          {Vxpipe.AgentRuntime.TestModelContextSource, test_owner},
          %{},
          timeout_ms: 10
        )
      end)

    assert_receive {:model_context_requested, source, %{}, 10}
    source_monitor = Process.monitor(source)

    assert {:ok, {:error, :model_context_unavailable}} = Task.yield(fetch_task, 200)
    assert_receive {:DOWN, ^source_monitor, :process, ^source, _reason}
  end

  defp fetch(result, options \\ []) do
    owner = self()

    task =
      Task.async(fn ->
        ModelContext.fetch(
          {Vxpipe.AgentRuntime.TestModelContextSource, owner},
          %{},
          options
        )
      end)

    assert_receive {:model_context_requested, source, %{}, _timeout}
    send(source, {:model_context_result, result})
    Task.await(task)
  end
end
