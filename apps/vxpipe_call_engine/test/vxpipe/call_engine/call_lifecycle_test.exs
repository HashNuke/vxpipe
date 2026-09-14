defmodule Vxpipe.CallEngine.CallLifecycleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallLifecycle, ResolvedCallPlan, TestCallLifecycleTimer}

  @startup_progress [:vxpipe, :call_engine, :startup, :progress]
  @startup_stop [:vxpipe, :call_engine, :startup, :stop]

  for outcome <- [:ready, :failed, :timeout] do
    test "reports #{outcome} startup once with safe current blockers and elapsed time" do
      handler = {__MODULE__, self(), make_ref()}
      incarnation = unique_id("private-incarnation")

      lifecycle =
        [
          plan: plan(),
          incarnation_id: incarnation,
          call_lifecycle: [
            readiness_timeout_ms: 30_000,
            idle_timeout_ms: 15_000,
            timer: {TestCallLifecycleTimer, [observer: self()]}
          ]
        ]
        |> CallLifecycle.child_spec()
        |> Map.put(:significant, false)
        |> start_supervised!()

      :ok =
        :telemetry.attach_many(
          handler,
          [@startup_progress, @startup_stop],
          &__MODULE__.handle_event/4,
          {self(), lifecycle}
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert_receive {:test_call_lifecycle_timer_scheduled, _, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert :ok = CallLifecycle.startup_progress(lifecycle, :configuration, [:model_inference])

      assert_receive {:startup_telemetry, @startup_progress, %{count: 1, duration: duration},
                      %{blockers: [:model_inference]}}

      assert duration >= 0

      assert :ok =
               CallLifecycle.startup_progress(lifecycle, :resources, [
                 :speech_to_text,
                 :model_inference
               ])

      assert_receive {:startup_telemetry, @startup_progress, _,
                      %{blockers: [:model_inference, :speech_to_text]}}

      assert :ok = CallLifecycle.startup_progress(lifecycle, :configuration, [])
      refute_receive {:startup_telemetry, @startup_progress, _, _}

      assert :ok =
               CallLifecycle.startup_progress(lifecycle, :resources, [
                 :speech_to_text,
                 "private-provider-payload"
               ])

      assert_receive {:startup_telemetry, @startup_progress, _,
                      %{blockers: [:other, :speech_to_text]}}

      case unquote(outcome) do
        :ready -> assert :ok = CallLifecycle.ready(lifecycle)
        :failed -> assert :ok = CallLifecycle.startup_failed(incarnation, :private_failure_reason)
        :timeout -> assert :ok = TestCallLifecycleTimer.fire(readiness_timer)
      end

      assert_receive {:startup_telemetry, @startup_stop, %{count: 1, duration: elapsed}, metadata}
      assert elapsed >= duration
      expected = if unquote(outcome) == :ready, do: [], else: [:other, :speech_to_text]
      assert metadata == %{outcome: unquote(outcome), blockers: expected}
      assert :ok = CallLifecycle.startup_progress(lifecycle, :resources, [:text_to_speech])
      _ = CallLifecycle.ready(lifecycle)
      _ = CallLifecycle.startup_failed(incarnation, :private_failure_reason)
      refute_receive {:startup_telemetry, _, _, _}
    end
  end

  def handle_event(event, measurements, metadata, {receiver, source}) do
    if self() == source, do: send(receiver, {:startup_telemetry, event, measurements, metadata})
  end

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
