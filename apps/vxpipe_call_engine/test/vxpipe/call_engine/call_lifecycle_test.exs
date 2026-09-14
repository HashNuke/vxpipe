defmodule Vxpipe.CallEngine.CallLifecycleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallLifecycle, ResolvedCallPlan, TestCallLifecycleTimer}

  for event <- [:readiness, :max_duration] do
    test "rejects readiness after #{event} fires before room authority binds" do
      incarnation_id = unique_id("incarnation")

      options = [
        plan: plan(),
        incarnation_id: incarnation_id,
        call_lifecycle: [
          readiness_timeout_ms: 30_000,
          idle_timeout_ms: 15_000,
          timer: {TestCallLifecycleTimer, [observer: self()]}
        ]
      ]

      lifecycle =
        options
        |> CallLifecycle.child_spec()
        |> Map.put(:significant, false)
        |> start_supervised!()

      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

      timer = if unquote(event) == :readiness, do: readiness_timer, else: maximum_timer
      :ok = TestCallLifecycleTimer.fire(timer)
      _ = :sys.get_state(lifecycle)

      assert {:ok, ^lifecycle} = CallLifecycle.bind(incarnation_id, self())
      assert_receive {:vxpipe_call_lifecycle, ^lifecycle, unquote(event)}
      assert {:error, :unavailable} = CallLifecycle.ready(lifecycle)
    end
  end

  defp plan do
    %ResolvedCallPlan{
      definition_id: "definition-lifecycle",
      definition_revision: 1,
      schema_version: "20260913.01",
      tenant_id: "tenant-lifecycle",
      actor_id: "actor-lifecycle",
      call_id: unique_id("call"),
      room_id: unique_id("room"),
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio: nil,
      media_policy: Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy.inherit(),
      participants: %{},
      transfer_policy: %Vxpipe.CallEngine.CallDefinition.TransferPolicy{
        attempt_timeout_ms: 30_000
      },
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 60_000
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
