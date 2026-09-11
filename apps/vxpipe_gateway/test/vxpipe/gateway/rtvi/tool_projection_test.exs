defmodule Vxpipe.Gateway.RTVI.ToolProjectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed, ToolCallStarted}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.RTVI.ToolProjection

  test "hides tool events by default" do
    policy = %ToolVisibility{default: :hidden, overrides: %{}}

    assert :hidden = ToolProjection.encode(started_event("part-reception"), policy)
    assert :hidden = ToolProjection.encode(completed_event("part-reception"), policy)
  end

  test "metadata omits arguments and results while full includes them" do
    metadata = %ToolVisibility{default: :metadata, overrides: %{}}
    full = %ToolVisibility{default: :full, overrides: %{}}

    assert {:ok, encoded} = ToolProjection.encode(started_event("part-reception"), metadata)

    assert %{
             "type" => "llm-function-call-in-progress",
             "data" => %{
               "tool_call_id" => "tool-1",
               "function_name" => "lookup_customer"
             }
           } = JSON.decode!(encoded)

    refute Map.has_key?(JSON.decode!(encoded)["data"], "arguments")

    assert {:ok, encoded} = ToolProjection.encode(completed_event("part-reception"), metadata)
    refute Map.has_key?(JSON.decode!(encoded)["data"], "result")

    assert {:ok, encoded} = ToolProjection.encode(failed_event("part-reception"), metadata)
    refute Map.has_key?(JSON.decode!(encoded)["data"], "result")

    assert {:ok, encoded} = ToolProjection.encode(started_event("part-reception"), full)
    assert JSON.decode!(encoded)["data"]["arguments"] == %{"customer_id" => "customer-1"}

    assert {:ok, encoded} = ToolProjection.encode(completed_event("part-reception"), full)
    assert JSON.decode!(encoded)["data"]["result"] == %{"status" => "found"}
  end

  test "resolves the same local tool name independently for each participant" do
    policy = %ToolVisibility{
      default: :hidden,
      overrides: %{
        "part-reception" => %{"lookup_customer" => :metadata},
        "part-billing" => %{"lookup_customer" => :full}
      }
    }

    assert {:ok, reception} =
             ToolProjection.encode(started_event("part-reception"), policy)

    refute Map.has_key?(JSON.decode!(reception)["data"], "arguments")

    assert {:ok, billing} = ToolProjection.encode(started_event("part-billing"), policy)

    assert JSON.decode!(billing)["data"]["arguments"] == %{
             "customer_id" => "customer-1"
           }
  end

  test "keeps internal transfer failure details out of full client visibility" do
    policy = %ToolVisibility{default: :full, overrides: %{}}

    event = %{
      failed_event("part-reception")
      | name: "transfer",
        reason: :destination_participant_unavailable
    }

    assert {:ok, encoded} = ToolProjection.encode(event, policy)

    assert %{
             "type" => "llm-function-call-stopped",
             "data" => %{
               "tool_call_id" => "tool-1",
               "function_name" => "transfer",
               "result" => %{"error" => "tool_failed"}
             }
           } = JSON.decode!(encoded)

    refute encoded =~ "destination_participant_unavailable"
  end

  defp started_event(participant_id) do
    fields(participant_id)
    |> Map.put(:arguments, %{"customer_id" => "customer-1"})
    |> then(&struct!(ToolCallStarted, &1))
  end

  defp completed_event(participant_id) do
    fields(participant_id)
    |> Map.put(:id, "evt-tool-completed")
    |> Map.put(:result, %{"status" => "found"})
    |> then(&struct!(ToolCallCompleted, &1))
  end

  defp failed_event(participant_id) do
    fields(participant_id)
    |> Map.put(:id, "evt-tool-failed")
    |> Map.put(:reason, :tool_failed_with_private_detail)
    |> then(&struct!(ToolCallFailed, &1))
  end

  defp fields(participant_id) do
    %{
      id: "evt-tool-started",
      sequence: 3,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: participant_id,
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: "turn-tool",
      tool_call_id: "tool-1",
      name: "lookup_customer",
      occurred_at: ~U[2026-09-09 06:00:00.000Z]
    }
  end
end
