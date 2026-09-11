defmodule Vxpipe.CallEngine.Usage.ToolAttemptTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedHostTool

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationSubmission
  }

  alias Vxpipe.CallEngine.Usage.ToolAttempt

  test "records one accepted host invocation without retaining its arguments" do
    observed_at = ~U[2026-09-12 01:02:03.456Z]
    submission = submission(%{"private" => "must-not-leak"})

    assert {:ok, attempt, [observation]} =
             ToolAttempt.start("call-usage", "activation-usage", submission, observed_at)

    assert observation.attempt_id == attempt.attempt_id
    assert observation.capability == :tool
    assert observation.outcome == :in_progress
    assert observation.provider.name == "host_application"
    assert observation.provider.integration_id == nil
    assert observation.attribution.participant_id == "participant-agent"
    assert observation.attribution.activation_id == "activation-usage"
    assert observation.attribution.turn_id == "turn-demo"
    assert observation.attribution.tool_call_id == "invocation-one"
    assert observation.measurement.component == "invocations"
    assert observation.measurement.unit == :requests
    assert observation.measurement.quantity == 1
    assert observation.measurement.provenance == :locally_measured
    assert observation.observed_at == observed_at
    refute inspect(attempt) =~ "must-not-leak"
    refute inspect(observation) =~ "must-not-leak"
  end

  test "records terminal outcomes without retaining tool results" do
    submission = submission(%{"private" => "argument-secret"})
    assert {:ok, attempt, [_started]} = start(submission)

    completion = %InvocationCompletion{
      invocation_id: submission.invocation_id,
      tool_name: submission.tool_name,
      conversation_mode: submission.conversation_mode,
      context: submission.context,
      outcome: {:ok, %{"private" => "result-secret"}}
    }

    assert {:ok, [completed]} =
             ToolAttempt.finish(attempt, completion, ~U[2026-09-12 01:02:04.456Z])

    assert completed.attempt_id == attempt.attempt_id
    assert completed.outcome == :succeeded
    assert completed.measurement == nil
    refute inspect(completed) =~ "argument-secret"
    refute inspect(completed) =~ "result-secret"

    assert {:ok, [unknown]} =
             ToolAttempt.finish(
               attempt,
               %{completion | outcome: {:error, :unknown}},
               ~U[2026-09-12 01:02:05.456Z]
             )

    assert unknown.outcome == :unknown

    assert {:ok, [failed]} =
             ToolAttempt.finish(
               attempt,
               %{completion | outcome: {:error, :tool_failed}},
               ~U[2026-09-12 01:02:06.456Z]
             )

    assert failed.outcome == :failed
  end

  test "namespaces remote operations by their configured integration without inventing an ID" do
    binding = %InvocationBinding{
      name: "customer_lookup",
      conversation_mode: :blocking,
      handler: {:remote_mcp, self()},
      usage_integration_id: "customer-system"
    }

    assert {:ok, submission} =
             InvocationSubmission.new(
               binding,
               %{"customer_id" => "private"},
               context(),
               "mcp-one"
             )

    assert {:ok, _attempt, [observation]} = start(submission)

    assert observation.provider.name == "remote_mcp"
    assert observation.provider.integration_id == "customer-system"
    assert observation.provider.request_id == nil
    assert observation.provider.operation_id == nil
    assert observation.provider.session_id == nil
  end

  defp submission(arguments) do
    resolved = %ToolBinding{
      name: "submitted_host_tool",
      type: :host,
      conversation_mode: :blocking,
      action: TestSubmittedHostTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)

    assert {:ok, submission} =
             InvocationSubmission.new(binding, arguments, context(), "invocation-one")

    submission
  end

  defp start(submission) do
    ToolAttempt.start(
      "call-usage",
      "activation-usage",
      submission,
      ~U[2026-09-12 01:02:03.456Z]
    )
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
end
