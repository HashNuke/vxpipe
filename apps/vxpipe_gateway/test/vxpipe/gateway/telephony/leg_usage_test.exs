defmodule Vxpipe.Gateway.Telephony.LegUsageTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, LegUsage}
  alias Vxpipe.Gateway.TestFinalUsageRepository

  @started ~U[2026-10-15 12:00:00.000Z]

  test "final persistence retains every original observation independently of the live room" do
    {usage, observations} = finished_usage()
    [started, identified, connected, final] = observations
    assert started.provider.operation_id == nil
    assert identified.provider.operation_id == "carrier-leg"
    assert connected.outcome == :in_progress
    assert final.measurement.quantity == 5_000

    # A duplicate terminal callback and later local failure cannot regenerate usage.
    usage = usage |> LegUsage.observe(event(:ended, 20)) |> LegUsage.fail(:unknown)
    assert :ok = LegUsage.persist_final(usage, repository(&normalized_ack/1))
    for observation <- observations, do: assert_receive({:stored_carrier_usage, ^observation})
    refute_received {:stored_carrier_usage, _}
  end

  test "a partial storage failure retries the same immutable batch" do
    {usage, observations} = finished_usage()
    [first, second, third, _final] = observations
    remaining_failure = start_supervised!({Agent, fn -> true end})

    result = fn observation ->
      fail? =
        observation.id == third.id and
          Agent.get_and_update(remaining_failure, fn pending -> {pending, false} end)

      if fail?, do: {:error, :database_unavailable}, else: normalized_ack(observation)
    end

    options = repository(result)
    assert {:error, :usage_persistence_unavailable} = LegUsage.persist_final(usage, options)

    for observation <- [first, second, third],
        do: assert_receive({:stored_carrier_usage, ^observation})

    refute_received {:stored_carrier_usage, _}

    assert :ok = LegUsage.persist_final(usage, options)
    for observation <- observations, do: assert_receive({:stored_carrier_usage, ^observation})
    refute_received {:stored_carrier_usage, _}
  end

  test "non-final or missing usage cannot acknowledge cleanup" do
    usage = start_usage()
    options = repository(&normalized_ack/1)
    assert {:error, :usage_not_final} = LegUsage.persist_final(nil, options)
    assert {:error, :usage_not_final} = LegUsage.persist_final(usage, options)
    final = usage |> LegUsage.fail(:unknown) |> Map.put(:observations, [])
    assert {:error, :usage_not_final} = LegUsage.persist_final(final, options)
    refute_received {:stored_carrier_usage, _}
  end

  test "storage faults and mismatched acknowledgements never report success" do
    {usage, _observations} = finished_usage()

    for result <- [
          fn _ -> raise "private storage detail" end,
          fn _ -> throw(:private_storage_detail) end,
          fn _ -> :ok end,
          fn observation -> {:ok, %{observation | outcome: :unknown}} end,
          fn observation ->
            {:ok,
             %{observation | observed_at: DateTime.add(observation.observed_at, 1, :millisecond)}}
          end
        ] do
      assert {:error, :usage_persistence_unavailable} =
               LegUsage.persist_final(usage, repository(result))
    end
  end

  defp finished_usage do
    usage = start_usage()
    assert_receive {:test_usage_observations, [started]}
    usage = LegUsage.observe(usage, event(:answered, 1))
    assert_receive {:test_usage_observations, [identified]}
    assert_receive {:test_usage_observations, [connected]}
    usage = LegUsage.observe(usage, event(:ended, 6))
    assert_receive {:test_usage_observations, [final]}
    {usage, [started, identified, connected, final]}
  end

  defp start_usage do
    {:ok, service} =
      ConfiguredService.new(
        id: "telnyx-primary",
        ingress_key: "usage-ingress",
        scope: {:tenant, "tenant-usage"},
        provider: :telnyx,
        provider_connection_id: "application",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "synthetic",
        public_base_url: "https://voice.example.test",
        adapter: Vxpipe.Gateway.TestTelephonyAdapter
      )

    request = %OutboundLegRequest{
      tenant_id: "tenant-usage",
      actor_id: "actor-usage",
      call_id: "call-usage",
      room_id: "room-usage",
      incarnation_id: "rinc-usage",
      participant_id: "participant-usage",
      service_id: "telnyx-primary",
      to: "+15550001001"
    }

    LegUsage.start_outgoing(request, service, "leg-usage",
      usage_clock: fn -> @started end,
      usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
    )
  end

  defp event(kind, seconds) do
    %Event{
      kind: kind,
      provider: :telnyx,
      provider_call_control_id: "carrier-control",
      provider_call_leg_id: "carrier-leg",
      provider_call_session_id: "carrier-session",
      provider_event_id: "event-#{kind}",
      occurred_at: DateTime.add(@started, seconds, :second),
      occurred_at_provenance: :provider_reported,
      end_reason: if(kind == :ended, do: :hangup)
    }
  end

  defp repository(result), do: [usage_repository: {TestFinalUsageRepository, {self(), result}}]

  defp normalized_ack(observation) do
    {microseconds, _precision} = observation.observed_at.microsecond

    {:ok,
     %{observation | observed_at: %{observation.observed_at | microsecond: {microseconds, 6}}}}
  end
end
