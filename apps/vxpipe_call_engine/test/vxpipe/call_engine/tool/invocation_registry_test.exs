defmodule Vxpipe.CallEngine.Tool.InvocationRegistryTest do
  use ExUnit.Case, async: false

  @admission_event [:vxpipe, :call_engine, :background_tool, :admission]
  @handoff_event [:vxpipe, :call_engine, :background_tool, :handoff]
  @stop_event [:vxpipe, :call_engine, :background_tool, :stop]

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedInlineTool

  alias Vxpipe.CallEngine.Tool.{
    CompletionLease,
    Context,
    InvocationBinding,
    InvocationRegistry,
    InvocationStatus,
    InvocationSupervisor
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_inline_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_inline_tool_observer)
    end)
  end

  @doc false
  def handle_telemetry(event, measurements, metadata, test) do
    send(test, {:invocation_telemetry, event, measurements, metadata})
  end

  test "retains one idempotent invocation through leased completion and explicit consumption" do
    {registry, _supervisor} = start_registry(maximum_invocations: 1)
    context = context()
    blocking = host_binding(:blocking)

    assert {:accepted, :blocking} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "first"},
               context,
               "invocation-one"
             )

    assert_receive {:submitted_inline_tool_started, execution, "first"}

    assert {:ok,
            [
              %InvocationStatus{
                invocation_id: "invocation-one",
                tool_name: "submitted_inline_tool",
                conversation_mode: :blocking,
                source_turn_id: "turn-demo",
                status: :running
              }
            ]} = InvocationRegistry.snapshot(registry)

    assert {:accepted, :blocking} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "first"},
               context,
               "invocation-one"
             )

    refute_receive {:submitted_inline_tool_started, _duplicate, "first"}

    assert {:error, :rejected} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "changed"},
               context,
               "invocation-one"
             )

    assert {:error, :saturated} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "second"},
               context,
               "invocation-two"
             )

    send(execution, :release_submitted_inline_tool)
    assert_receive {:vxpipe_tool_completion_available, ^registry, "invocation-one"}

    assert {:ok, [%InvocationStatus{invocation_id: "invocation-one", status: :terminal_queued}]} =
             InvocationRegistry.snapshot(registry)

    assert {:error, :saturated} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "second"},
               context,
               "invocation-two"
             )

    assert {:ok,
            %CompletionLease{
              invocation_id: "invocation-one",
              consumer_id: "continuation-one",
              completion: completion,
              lease_id: first_lease_id
            }} = InvocationRegistry.lease_next(registry, "continuation-one")

    assert completion.outcome == {:ok, %{"value" => "first"}}
    refute inspect(:sys.get_state(registry)) =~ "first"
    refute inspect(completion) =~ "first"

    assert {:ok,
            [%InvocationStatus{invocation_id: "invocation-one", status: :completion_admitted}]} =
             InvocationRegistry.snapshot(registry)

    assert :ok =
             InvocationRegistry.release_completion(
               registry,
               "invocation-one",
               first_lease_id
             )

    assert_receive {:vxpipe_tool_completion_available, ^registry, "invocation-one"}

    assert {:ok, %CompletionLease{lease_id: second_lease_id}} =
             InvocationRegistry.lease_next(registry, "continuation-two")

    refute second_lease_id == first_lease_id

    assert :ok =
             InvocationRegistry.acknowledge_completion(
               registry,
               "invocation-one",
               second_lease_id
             )

    assert {:ok, []} = InvocationRegistry.snapshot(registry)

    assert {:error, :rejected} =
             InvocationRegistry.submit(
               registry,
               blocking,
               %{"value" => "first"},
               context,
               "invocation-one"
             )

    non_blocking = host_binding(:non_blocking)

    assert {:accepted, :non_blocking} =
             InvocationRegistry.submit(
               registry,
               non_blocking,
               %{"value" => "second"},
               context,
               "invocation-two"
             )

    assert_receive {:submitted_inline_tool_started, second_execution, "second"}
    send(second_execution, :release_submitted_inline_tool)
  end

  test "does not start work after bounded submission reports unavailable" do
    {registry, _supervisor} = start_registry(maximum_invocations: 1)
    :ok = :sys.suspend(registry)

    on_exit(fn ->
      try do
        :sys.resume(registry)
      catch
        :exit, _reason -> :ok
      end
    end)

    submission =
      Task.async(fn ->
        InvocationRegistry.submit(
          registry,
          host_binding(:blocking),
          %{"value" => "must-not-start"},
          context(),
          "expired-submission"
        )
      end)

    assert {:error, :unavailable} = Task.await(submission, 3_000)

    :ok = :sys.resume(registry)
    assert {:ok, []} = InvocationRegistry.snapshot(registry)
    refute_receive {:submitted_inline_tool_started, _execution, "must-not-start"}
  end

  test "emits bounded telemetry as submitted work is admitted, settled, and consumed" do
    attach_telemetry()
    {registry, _supervisor} = start_registry(maximum_invocations: 1)

    assert {:accepted, :non_blocking} =
             InvocationRegistry.submit(
               registry,
               host_binding(:non_blocking),
               %{"value" => "telemetry-private-value"},
               context(),
               "telemetry-private-invocation"
             )

    assert_receive {:invocation_telemetry, @admission_event, %{count: 1, reserved: 1, limit: 1},
                    %{outcome: :accepted}}

    assert_receive {:submitted_inline_tool_started, execution, "telemetry-private-value"}
    send(execution, :release_submitted_inline_tool)

    assert_receive {:invocation_telemetry, @stop_event, %{count: 1, duration: duration},
                    %{outcome: :ok}}

    assert is_integer(duration) and duration >= 0

    assert_receive {:invocation_telemetry, @handoff_event, %{count: 1, depth: 1, limit: 1},
                    %{outcome: :queued}}

    assert {:ok, %CompletionLease{lease_id: lease_id}} =
             InvocationRegistry.lease_next(registry, "telemetry-consumer")

    assert :ok =
             InvocationRegistry.acknowledge_completion(
               registry,
               "telemetry-private-invocation",
               lease_id
             )

    assert_receive {:invocation_telemetry, @handoff_event, %{count: 1, depth: 0, limit: 1},
                    %{outcome: :consumed}}
  end

  defp start_registry(options) do
    activation_id = "act-registry-#{System.unique_integer([:positive])}"
    maximum_invocations = Keyword.fetch!(options, :maximum_invocations)

    supervisor =
      start_supervised!(
        {InvocationSupervisor,
         activation_id: activation_id, maximum_children: maximum_invocations}
      )

    registry =
      start_supervised!(
        {InvocationRegistry,
         activation_id: activation_id,
         invocation_supervisor: supervisor,
         completion_target: self(),
         maximum_invocations: maximum_invocations,
         maximum_consumed_invocations: 4,
         invocation_timeout_ms: 1_000,
         maximum_result_bytes: 4_096}
      )

    {registry, supervisor}
  end

  defp host_binding(conversation_mode) do
    resolved = %ToolBinding{
      name: "submitted_inline_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedInlineTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)
    binding
  end

  defp context do
    %Context{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "incarnation-demo",
      agent_participant_id: "participant-agent",
      source_participant_id: "participant-caller",
      connection_id: "connection-caller",
      command_id: "command-demo",
      correlation_id: "turn-demo",
      agent_request_id: "request-demo",
      tool_call_id: nil
    }
  end

  defp attach_telemetry do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@admission_event, @stop_event, @handoff_event],
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
