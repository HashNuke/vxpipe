defmodule Vxpipe.CallEngine.CallLifecycleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallLifecycle, ResolvedCallPlan, TestCallLifecycleTimer}

  test "delivers a deadline that fires before room authority binds" do
    incarnation_id = unique_id("incarnation")

    options = [
      plan: plan(),
      incarnation_id: incarnation_id,
      call_lifecycle: [
        readiness_timeout_ms: 30_000,
        timer: {TestCallLifecycleTimer, [observer: self()]}
      ]
    ]

    lifecycle =
      options
      |> CallLifecycle.child_spec()
      |> Map.put(:significant, false)
      |> start_supervised!()

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    :ok = TestCallLifecycleTimer.fire(readiness_timer)
    _ = :sys.get_state(lifecycle)

    assert {:ok, ^lifecycle} = CallLifecycle.bind(incarnation_id, self())
    assert_receive {:vxpipe_call_lifecycle, ^lifecycle, :readiness}
  end

  defp plan do
    %ResolvedCallPlan{
      definition_id: "definition-lifecycle",
      definition_revision: 1,
      schema_version: "20260910.03",
      tenant_id: "tenant-lifecycle",
      actor_id: "actor-lifecycle",
      call_id: unique_id("call"),
      room_id: unique_id("room"),
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio: nil,
      participants: %{},
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 60_000
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
