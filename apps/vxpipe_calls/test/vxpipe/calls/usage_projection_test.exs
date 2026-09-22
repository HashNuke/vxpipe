defmodule Vxpipe.Calls.UsageProjectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Usage.{Attribution, EffectiveAmount, ProviderContext}
  alias Vxpipe.Calls.{CallFact, UsageObservationProjection, UsageReport}

  @occurred_at ~U[2026-09-12 08:00:00.000Z]

  test "restores one exact typed usage observation from its private archive fact" do
    assert {:ok, observation} = UsageObservationProjection.project(usage_fact())

    assert observation.id == "usage-fact-1"
    assert observation.tenant_id == "AAAAAAAAAAAAAAAA"
    assert observation.call_id == "call-usage"
    assert observation.attempt_id == "attempt-1"
    assert observation.capability == :model_inference
    assert observation.provider.name == "provider-fixture"
    assert observation.provider.request_id == "provider-request-1"
    assert observation.attribution.participant_id == "participant-agent"
    assert observation.attribution.turn_id == "turn-1"
    assert observation.measurement.unit == {:currency, "USD"}
    assert Decimal.equal?(observation.measurement.quantity, Decimal.new("0.0042"))
    assert observation.measurement.provenance == :billing_lookup
  end

  test "restores a speech-to-speech usage observation from its archive fact" do
    fact = usage_fact()
    payload = put_in(fact.payload, ["capability"], "speech_to_speech")

    assert {:ok, observation} = UsageObservationProjection.project(%{fact | payload: payload})
    assert observation.capability == :speech_to_speech
  end

  test "restores an agent-output speech-to-text usage observation from its archive fact" do
    fact = usage_fact()
    payload = put_in(fact.payload, ["capability"], "output_speech_to_text")

    assert {:ok, observation} = UsageObservationProjection.project(%{fact | payload: payload})
    assert observation.capability == :output_speech_to_text
  end

  test "rejects an archive payload whose attribution disagrees with the fact envelope" do
    fact = usage_fact()
    payload = put_in(fact.payload, ["attribution", "participant_id"], "participant-other")

    assert {:error, :invalid_usage_observation_fact} =
             UsageObservationProjection.project(%{fact | payload: payload})
  end

  test "aggregates root amounts without mixing evidence dimensions or double-counting children" do
    amounts = [
      amount("attempt-1", "total_tokens", :tokens, 100,
        request_id: "provider-request-1",
        observation_ids: ["observation-1"]
      ),
      amount("attempt-2", "total_tokens", :tokens, 60,
        request_id: "provider-request-2",
        observation_ids: ["observation-2"]
      ),
      amount("attempt-1", "input_tokens", :tokens, 80,
        included_in: "total_tokens",
        request_id: "provider-request-1",
        observation_ids: ["observation-child"]
      ),
      amount("attempt-3", "cost", {:currency, "USD"}, Decimal.new("0.0042"),
        observation_ids: ["observation-cost-usd-1"]
      ),
      amount("attempt-4", "cost", {:currency, "USD"}, Decimal.new("0.0018"),
        observation_ids: ["observation-cost-usd-2"]
      ),
      amount("attempt-5", "cost", {:currency, "EUR"}, Decimal.new("0.0020"),
        observation_ids: ["observation-cost-eur"]
      ),
      amount("attempt-6", "total_tokens", :tokens, 20,
        participant_id: "participant-other",
        turn_id: "turn-2",
        observation_ids: ["observation-other-participant"]
      )
    ]

    assert {:ok, report} = UsageReport.new(amounts)
    assert report.amounts == amounts
    assert length(report.totals) == 4

    grouped = Map.new(report.totals, &{{&1.participant_id, &1.turn_id, &1.unit}, &1})

    assert grouped[{"participant-agent", "turn-1", :tokens}].quantity == 160
    assert grouped[{"participant-agent", "turn-1", :tokens}].amount_count == 2
    assert grouped[{"participant-other", "turn-2", :tokens}].quantity == 20

    assert Decimal.equal?(
             grouped[{"participant-agent", "turn-1", {:currency, "USD"}}].quantity,
             Decimal.new("0.0060")
           )

    assert Decimal.equal?(
             grouped[{"participant-agent", "turn-1", {:currency, "EUR"}}].quantity,
             Decimal.new("0.0020")
           )

    refute Enum.any?(report.totals, &(&1.quantity == 80))
  end

  defp usage_fact do
    {:ok, fact} =
      CallFact.new(
        id: "usage-fact-1",
        kind: :usage_observed,
        sequence: 1,
        tenant_key: "AAAAAAAAAAAAAAAA",
        call_id: "call-usage",
        room_id: "room-usage",
        incarnation_id: "incarnation-usage",
        participant_id: "participant-agent",
        activation_id: "activation-agent",
        correlation_id: "turn-1",
        occurred_at: @occurred_at,
        source_policy: %{"revision" => 1},
        payload: %{
          "attempt_id" => "attempt-1",
          "capability" => "model_inference",
          "delivery_id" => "billing-delivery-1",
          "source_sequence" => 7,
          "outcome" => "succeeded",
          "provider" => %{
            "name" => "provider-fixture",
            "integration_id" => "model-primary",
            "model" => "fixture-model",
            "request_id" => "provider-request-1"
          },
          "attribution" => %{
            "room_id" => "room-usage",
            "incarnation_id" => "incarnation-usage",
            "participant_id" => "participant-agent",
            "activation_id" => "activation-agent",
            "turn_id" => "turn-1"
          },
          "measurement" => %{
            "component" => "cost",
            "unit" => %{"currency" => "USD"},
            "quantity" => "0.0042",
            "mode" => "cumulative",
            "status" => "final",
            "provenance" => "billing_lookup"
          }
        }
      )

    fact
  end

  defp amount(attempt_id, component, unit, quantity, options) do
    participant_id = Keyword.get(options, :participant_id, "participant-agent")
    turn_id = Keyword.get(options, :turn_id, "turn-1")

    %EffectiveAmount{
      attempt_id: attempt_id,
      capability: :model_inference,
      provider: %ProviderContext{
        name: "provider-fixture",
        integration_id: "model-primary",
        model: "fixture-model",
        voice: nil,
        request_id: Keyword.get(options, :request_id),
        operation_id: nil,
        session_id: nil
      },
      attribution: %Attribution{
        room_id: "room-usage",
        incarnation_id: "incarnation-usage",
        participant_id: participant_id,
        activation_id: "activation-agent",
        service_interval_id: nil,
        leg_id: nil,
        turn_id: turn_id,
        utterance_id: nil,
        tool_call_id: nil
      },
      component: component,
      unit: unit,
      quantity: quantity,
      mode: :cumulative,
      status: :final,
      provenance: :provider_reported,
      included_in: Keyword.get(options, :included_in),
      observation_ids: Keyword.fetch!(options, :observation_ids)
    }
  end
end
