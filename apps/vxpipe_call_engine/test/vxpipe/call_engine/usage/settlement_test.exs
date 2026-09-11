defmodule Vxpipe.CallEngine.Usage.SettlementTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Measurement,
    Observation,
    ProviderContext,
    Settlement
  }

  @observed_at ~U[2026-09-11 21:45:00Z]

  test "keeps provider identity and honest call, participant, and turn attribution typed" do
    assert {:ok, attribution} =
             Attribution.new(
               room_id: "room-usage",
               incarnation_id: "incarnation-usage",
               participant_id: "participant-agent",
               activation_id: "activation-agent",
               turn_id: "turn-usage"
             )

    assert {:ok, provider} =
             ProviderContext.new(
               name: "provider-fixture",
               integration_id: "model-primary",
               model: "fixture-model",
               request_id: "provider-request-1"
             )

    assert {:ok, measurement} =
             Measurement.new(
               component: "input_tokens",
               unit: :tokens,
               quantity: 100,
               mode: :cumulative,
               status: :final,
               provenance: :provider_reported
             )

    assert {:ok, observation} =
             Observation.new(
               id: "usage-observation-1",
               delivery_id: "provider-delivery-1",
               source_sequence: 1,
               tenant_id: "tenant-usage",
               call_id: "call-usage",
               attempt_id: "model-attempt-1",
               capability: :model_inference,
               provider: provider,
               attribution: attribution,
               measurement: measurement,
               outcome: :succeeded,
               observed_at: @observed_at
             )

    assert observation.provider.request_id == "provider-request-1"
    assert observation.attribution.participant_id == "participant-agent"
    assert observation.attribution.turn_id == "turn-usage"
    refute Map.has_key?(Map.from_struct(observation.attribution), :participant_type)
    refute inspect(observation) =~ "provider-request-1"
  end

  test "adds distinct deltas, deduplicates proven delivery, and never lets finality replace a delta" do
    observations = [
      observation("delta-1", 100, delivery_id: "delivery-1", status: :final),
      observation("delta-2", 60, delivery_id: "delivery-2", status: :final),
      observation("delta-2-replayed", 60, delivery_id: "delivery-2", status: :final)
    ]

    assert {:ok, settlement} = Settlement.derive(observations)
    assert [amount] = settlement.amounts
    assert amount.quantity == 160
    assert amount.mode == :delta
    assert amount.status == :final
    assert amount.observation_ids == ["delta-1", "delta-2"]
    assert {:ok, 160} = Settlement.total(settlement, :tokens)

    equal_but_distinct = [
      observation("equal-1", 50, attempt_id: "model-attempt-2"),
      observation("equal-2", 50, attempt_id: "model-attempt-2")
    ]

    assert {:ok, distinct} = Settlement.derive(equal_but_distinct)
    assert {:ok, 100} = Settlement.total(distinct, :tokens)

    repeated_source_sequence = [
      observation("source-original", 25,
        delivery_id: "source-delivery-1",
        source_sequence: 7
      ),
      observation("source-replayed", 25,
        delivery_id: "source-delivery-2",
        source_sequence: 7
      )
    ]

    assert {:ok, by_sequence} = Settlement.derive(repeated_source_sequence)
    assert {:ok, 25} = Settlement.total(by_sequence, :tokens)

    repeated_observation = [
      observation("stable-observation-id", 30, delivery_id: "observation-delivery-1"),
      observation("stable-observation-id", 30, delivery_id: "observation-delivery-2")
    ]

    assert {:ok, by_observation} = Settlement.derive(repeated_observation)
    assert {:ok, 30} = Settlement.total(by_observation, :tokens)
  end

  test "replaces cumulative estimates by sequence while finals and corrections remain authoritative" do
    observations = [
      observation("cumulative-100", 100,
        attempt_id: "model-attempt-cumulative",
        mode: :cumulative,
        source_sequence: 1
      ),
      observation("cumulative-160", 160,
        attempt_id: "model-attempt-cumulative",
        mode: :cumulative,
        source_sequence: 2
      ),
      observation("estimate-1000", 1_000,
        attempt_id: "model-attempt-corrected",
        mode: :cumulative,
        source_sequence: 1
      ),
      observation("estimate-1600", 1_600,
        attempt_id: "model-attempt-corrected",
        mode: :cumulative,
        source_sequence: 2
      ),
      observation("final-1700", 1_700,
        attempt_id: "model-attempt-corrected",
        mode: :cumulative,
        status: :final,
        source_sequence: 3
      ),
      observation("correction-1650", 1_650,
        attempt_id: "model-attempt-corrected",
        mode: :cumulative,
        status: :correction,
        source_sequence: 4
      ),
      observation("stale-estimate-1800", 1_800,
        attempt_id: "model-attempt-corrected",
        mode: :cumulative,
        source_sequence: 5
      )
    ]

    assert {:ok, settlement} = Settlement.derive(observations)

    amounts = Map.new(settlement.amounts, &{&1.attempt_id, &1})
    assert amounts["model-attempt-cumulative"].quantity == 160
    assert amounts["model-attempt-cumulative"].status == :estimate
    assert amounts["model-attempt-corrected"].quantity == 1_650
    assert amounts["model-attempt-corrected"].status == :correction
  end

  test "retains included token categories without counting them in addition to their total" do
    observations = [
      observation("total", 160, component: "total_tokens"),
      observation("input", 100,
        component: "input_tokens",
        included_in: "total_tokens"
      ),
      observation("output", 60,
        component: "output_tokens",
        included_in: "total_tokens"
      )
    ]

    assert {:ok, settlement} = Settlement.derive(observations)

    assert Enum.map(settlement.amounts, & &1.component) == [
             "input_tokens",
             "output_tokens",
             "total_tokens"
           ]

    assert {:ok, 160} = Settlement.total(settlement, :tokens)
  end

  test "keeps monetary quantities exact and separates currencies" do
    observations = [
      observation("usd-1", "0.0012",
        attempt_id: "cost-attempt-usd",
        component: "cost",
        unit: {:currency, "USD"}
      ),
      observation("usd-2", "0.0034",
        attempt_id: "cost-attempt-usd",
        component: "cost",
        unit: {:currency, "USD"}
      ),
      observation("eur-1", "0.0100",
        attempt_id: "cost-attempt-eur",
        component: "cost",
        unit: {:currency, "EUR"}
      )
    ]

    assert {:ok, settlement} = Settlement.derive(observations)
    assert {:ok, usd} = Settlement.total(settlement, {:currency, "USD"})
    assert {:ok, eur} = Settlement.total(settlement, {:currency, "EUR"})
    assert Decimal.equal?(usd, Decimal.new("0.0046"))
    assert Decimal.equal?(eur, Decimal.new("0.0100"))

    assert {:error, :invalid_measurement} =
             Measurement.new(
               component: "cost",
               unit: {:currency, "USD"},
               quantity: 0.1,
               mode: :delta,
               status: :estimate,
               provenance: :provider_reported
             )
  end

  test "does not silently add different cost provenances into one monetary total" do
    observations = [
      observation("reported-cost", "0.0100",
        attempt_id: "priced-attempt",
        component: "cost",
        unit: {:currency, "USD"},
        provenance: :provider_reported
      ),
      observation("estimated-cost", "0.0110",
        attempt_id: "priced-attempt",
        component: "cost",
        unit: {:currency, "USD"},
        provenance: :library_estimate
      )
    ]

    assert {:ok, settlement} = Settlement.derive(observations)
    assert {:error, :ambiguous_provenance} = Settlement.total(settlement, {:currency, "USD"})

    assert {:ok, reported} =
             Settlement.total(settlement, {:currency, "USD"}, provenance: :provider_reported)

    assert Decimal.equal?(reported, Decimal.new("0.0100"))
  end

  defp observation(id, quantity, options) do
    component = Keyword.get(options, :component, "input_tokens")
    unit = Keyword.get(options, :unit, :tokens)

    assert {:ok, measurement} =
             Measurement.new(
               component: component,
               unit: unit,
               quantity: quantity,
               mode: Keyword.get(options, :mode, :delta),
               status: Keyword.get(options, :status, :estimate),
               provenance: Keyword.get(options, :provenance, :provider_reported),
               included_in: Keyword.get(options, :included_in)
             )

    assert {:ok, provider} =
             ProviderContext.new(name: "provider-fixture", integration_id: "primary")

    assert {:ok, attribution} = Attribution.new(participant_id: "participant-agent")

    assert {:ok, observation} =
             Observation.new(
               id: id,
               delivery_id: Keyword.get(options, :delivery_id),
               source_sequence: Keyword.get(options, :source_sequence),
               tenant_id: "tenant-usage",
               call_id: "call-usage",
               attempt_id: Keyword.get(options, :attempt_id, "model-attempt-1"),
               capability: :model_inference,
               provider: provider,
               attribution: attribution,
               measurement: measurement,
               outcome: :succeeded,
               observed_at: @observed_at
             )

    observation
  end
end
