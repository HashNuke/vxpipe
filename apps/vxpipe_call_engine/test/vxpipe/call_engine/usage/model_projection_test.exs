defmodule Vxpipe.CallEngine.Usage.ModelProjectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.Tool.Context

  alias Vxpipe.CallEngine.Usage.{
    ModelProjection,
    Observation,
    ProviderContext
  }

  @observed_at ~U[2026-09-11 22:15:00.123Z]

  test "projects one completed model round without retaining arbitrary provider metadata" do
    provider = provider_context()

    data = %{
      usage: %{
        input_tokens: 12,
        output_tokens: 4,
        total_tokens: 16,
        total_cost: 0.0042,
        unrecognized_usage: "private-usage-value"
      },
      provider_metadata: %{
        model: "google:gemini-fixture",
        request_id: "provider-request-1",
        response_id: "provider-response-1",
        session_id: "provider-session-1",
        authorization: "private-provider-value"
      }
    }

    assert {:ok, observations} =
             ModelProjection.project(data, correlation(), provider,
               call_id: "call-usage",
               activation_id: "activation-agent",
               attempt_id: "model-attempt-1",
               observed_at: @observed_at
             )

    assert [input, output, total] = Enum.sort_by(observations, & &1.measurement.component)

    assert %Observation{
             attempt_id: "model-attempt-1",
             capability: :model_inference,
             tenant_id: "tenant-usage",
             call_id: "call-usage",
             outcome: :succeeded,
             observed_at: @observed_at
           } = input

    assert input.measurement.component == "input_tokens"
    assert input.measurement.quantity == 12
    assert input.measurement.included_in == "total_tokens"
    assert output.measurement.component == "output_tokens"
    assert output.measurement.quantity == 4
    assert output.measurement.included_in == "total_tokens"
    assert total.measurement.component == "total_tokens"
    assert total.measurement.quantity == 16
    assert total.measurement.included_in == nil

    assert input.provider == output.provider
    assert output.provider == total.provider
    assert input.provider.name == "google"
    assert input.provider.integration_id == "primary-model"
    assert input.provider.model == "google:gemini-fixture"
    assert input.provider.request_id == "provider-request-1"
    assert input.provider.operation_id == "provider-response-1"
    assert input.provider.session_id == "provider-session-1"

    assert input.attribution.room_id == "room-usage"
    assert input.attribution.incarnation_id == "incarnation-usage"
    assert input.attribution.participant_id == "participant-agent"
    assert input.attribution.activation_id == "activation-agent"
    assert input.attribution.turn_id == "turn-usage"
    assert input.attribution.tool_call_id == nil

    assert observations |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 3
    refute inspect(observations) =~ "private-provider-value"
    refute inspect(observations) =~ "private-usage-value"
    refute Enum.any?(observations, &(&1.measurement.component == "cost"))
  end

  test "retains the model operation when supported usage is unavailable" do
    assert {:ok, [observation]} =
             ModelProjection.project(
               %{
                 usage: %{input_tokens: "unknown"},
                 provider_metadata: %{request_id: "provider-request-2"}
               },
               correlation(),
               provider_context(),
               call_id: "call-usage",
               activation_id: "activation-agent",
               attempt_id: "model-attempt-2",
               observed_at: @observed_at,
               tool_call_id: "tool-call-1"
             )

    assert observation.measurement == nil
    assert String.starts_with?(observation.id, "uobs_")
    assert observation.provider.request_id == "provider-request-2"
    assert observation.attribution.tool_call_id == "tool-call-1"
  end

  test "names compaction measurements separately without inventing another turn" do
    assert {:ok, observations} =
             ModelProjection.project(
               %{usage: %{input_tokens: 25, output_tokens: 7, total_tokens: 32}},
               correlation(),
               provider_context(),
               call_id: "call-usage",
               activation_id: "activation-agent",
               attempt_id: "model-attempt-compaction",
               observed_at: @observed_at,
               purpose: :context_compaction
             )

    measurements = Enum.map(observations, & &1.measurement)

    assert Enum.map(measurements, & &1.component) == [
             "context_compaction_input_tokens",
             "context_compaction_output_tokens",
             "context_compaction_total_tokens"
           ]

    assert Enum.map(measurements, & &1.included_in) == [
             "context_compaction_total_tokens",
             "context_compaction_total_tokens",
             nil
           ]

    assert Enum.all?(observations, &(&1.attribution.turn_id == "turn-usage"))
  end

  test "retains a failed compaction operation when token usage is unavailable" do
    assert {:ok, [observation]} =
             ModelProjection.project(
               %{usage: %{}, provider_metadata: %{}},
               correlation(),
               provider_context(),
               call_id: "call-usage",
               activation_id: "activation-agent",
               attempt_id: "model-attempt-failed-compaction",
               observed_at: @observed_at,
               outcome: :failed,
               purpose: :context_compaction
             )

    assert observation.measurement == nil
    assert observation.outcome == :failed
    assert String.starts_with?(observation.id, "uobs_")
  end

  defp provider_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "configured-provider",
               integration_id: "primary-model",
               model: "configured:model"
             )

    provider
  end

  defp correlation do
    Correlation.new(
      :usage_projection_registry,
      %Context{
        tenant_id: "tenant-usage",
        room_id: "room-usage",
        incarnation_id: "incarnation-usage",
        agent_participant_id: "participant-agent",
        source_participant_id: "participant-caller",
        connection_id: "connection-caller",
        command_id: "command-usage",
        correlation_id: "turn-usage",
        agent_request_id: "agent-request-usage",
        tool_call_id: nil,
        audio_response: true
      }
    )
  end
end
