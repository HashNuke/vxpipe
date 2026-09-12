defmodule Vxpipe.CallEngine.Usage.TelephonyAttemptTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Usage.{ProviderContext, TelephonyAttempt}

  @started_at ~U[2026-09-12 04:00:00.000Z]
  @connected_at ~U[2026-09-12 04:00:03.250Z]
  @ended_at ~U[2026-09-12 04:01:08.750Z]

  test "records one carrier leg and a provider-timed connected duration" do
    assert {:ok, attempt, [started]} =
             TelephonyAttempt.start(
               identity(),
               "tleg-usage-1",
               provider_context(),
               @started_at
             )

    assert started.capability == :telephony
    assert started.outcome == :in_progress
    assert started.attempt_id == "tleg-usage-1"
    assert started.measurement.component == "carrier_legs"
    assert started.measurement.unit == :requests
    assert started.measurement.quantity == 1
    assert started.measurement.provenance == :locally_measured
    assert started.attribution.leg_id == "tleg-usage-1"
    assert started.attribution.participant_id == "participant-caller"
    assert started.attribution.activation_id == nil

    assert {:ok, attempt, [identified]} =
             TelephonyAttempt.identify(
               attempt,
               "provider-leg-1",
               "provider-session-1",
               @started_at
             )

    assert identified.measurement == nil
    assert identified.provider.operation_id == "provider-leg-1"
    assert identified.provider.session_id == "provider-session-1"

    {attempt, [connected]} =
      TelephonyAttempt.connect(attempt, @connected_at,
        provenance: :provider_reported,
        delivery_id: "provider-event-answered",
        source_sequence: 2
      )

    assert connected.outcome == :in_progress
    assert connected.measurement == nil
    assert connected.delivery_id == "provider-event-answered"
    assert connected.source_sequence == 2

    assert {attempt, {:ok, [duration]}} =
             TelephonyAttempt.finish(attempt, :succeeded, @ended_at,
               provenance: :provider_reported,
               delivery_id: "provider-event-ended",
               source_sequence: 3
             )

    assert duration.outcome == :succeeded
    assert duration.measurement.component == "connection_duration"
    assert duration.measurement.unit == :milliseconds
    assert duration.measurement.quantity == 65_500
    assert duration.measurement.provenance == :provider_reported
    assert duration.delivery_id == "provider-event-ended"
    assert duration.source_sequence == 3
    assert duration.provider.operation_id == "provider-leg-1"
    assert duration.provider.session_id == "provider-session-1"

    assert {^attempt, {:ok, []}} =
             TelephonyAttempt.finish(attempt, :succeeded, @ended_at,
               provenance: :provider_reported
             )
  end

  test "retains a failed leg without inventing connection duration" do
    assert {:ok, attempt, [_started]} =
             TelephonyAttempt.start(
               identity(),
               "tleg-usage-2",
               provider_context(),
               @started_at
             )

    assert {attempt, {:ok, [failed]}} =
             TelephonyAttempt.finish(attempt, :failed, @ended_at, provenance: :locally_measured)

    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert failed.provider.operation_id == nil

    assert {^attempt, []} =
             TelephonyAttempt.connect(attempt, @connected_at, provenance: :provider_reported)
  end

  test "does not derive duration from regressing carrier timestamps" do
    assert {:ok, attempt, [_started]} =
             TelephonyAttempt.start(
               identity(),
               "tleg-usage-3",
               provider_context(),
               @started_at
             )

    {attempt, [_connected]} =
      TelephonyAttempt.connect(attempt, @ended_at, provenance: :provider_reported)

    assert {_attempt, {:ok, [ended]}} =
             TelephonyAttempt.finish(attempt, :unknown, @connected_at,
               provenance: :provider_reported
             )

    assert ended.outcome == :unknown
    assert ended.measurement == nil
  end

  test "a local cancellation stays measurable without claiming a carrier end time" do
    assert {:ok, attempt, [_started]} =
             TelephonyAttempt.start(
               identity(),
               "tleg-usage-4",
               provider_context(),
               @started_at
             )

    {attempt, [_connected]} =
      TelephonyAttempt.connect(attempt, @connected_at, provenance: :provider_reported)

    assert {_attempt, {:ok, [cancelled]}} =
             TelephonyAttempt.finish(attempt, :cancelled, @ended_at,
               provenance: :locally_measured,
               duration: :unavailable
             )

    assert cancelled.outcome == :cancelled
    assert cancelled.measurement == nil
  end

  test "later carrier evidence improves a locally observed connected boundary" do
    assert {:ok, attempt, [_started]} =
             TelephonyAttempt.start(
               identity(),
               "tleg-usage-5",
               provider_context(),
               @started_at
             )

    locally_observed_at = DateTime.add(@connected_at, 2_000, :millisecond)

    {attempt, [_connected]} =
      TelephonyAttempt.connect(attempt, locally_observed_at, provenance: :locally_measured)

    {attempt, []} =
      TelephonyAttempt.connect(attempt, @connected_at, provenance: :provider_reported)

    assert {_attempt, {:ok, [duration]}} =
             TelephonyAttempt.finish(attempt, :succeeded, @ended_at,
               provenance: :provider_reported
             )

    assert duration.measurement.quantity == 65_500
    assert duration.measurement.provenance == :provider_reported
  end

  defp identity do
    %{
      tenant_id: "tenant-usage",
      call_id: "call-usage",
      room_id: "room-usage",
      incarnation_id: "incarnation-usage",
      participant_id: "participant-caller"
    }
  end

  defp provider_context do
    assert {:ok, provider} =
             ProviderContext.new(name: "telnyx", integration_id: "primary-phone")

    provider
  end
end
