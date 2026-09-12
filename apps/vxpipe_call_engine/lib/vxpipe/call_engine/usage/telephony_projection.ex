defmodule Vxpipe.CallEngine.Usage.TelephonyProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, TelephonyAttempt}

  @type evidence :: keyword()

  @spec started(TelephonyAttempt.t(), DateTime.t()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_telephony_usage}
  def started(%TelephonyAttempt{} = attempt, %DateTime{} = observed_at) do
    with {:ok, measurement} <- carrier_leg_measurement(),
         {:ok, observation} <-
           build(attempt, measurement, :in_progress, observed_at, [], "carrier_legs") do
      {:ok, [observation]}
    else
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  @spec identified(TelephonyAttempt.t(), DateTime.t()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_telephony_usage}
  def identified(%TelephonyAttempt{} = attempt, %DateTime{} = observed_at) do
    case build(attempt, nil, :in_progress, observed_at, [], "provider_identity") do
      {:ok, observation} -> {:ok, [observation]}
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  @spec connected(TelephonyAttempt.t(), DateTime.t(), evidence()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_telephony_usage}
  def connected(%TelephonyAttempt{} = attempt, %DateTime{} = observed_at, evidence) do
    case build(attempt, nil, :in_progress, observed_at, evidence, "connected") do
      {:ok, observation} -> {:ok, [observation]}
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  @spec terminal(
          TelephonyAttempt.t(),
          Observation.outcome(),
          DateTime.t(),
          evidence()
        ) :: {:ok, [Observation.t()]} | {:error, :invalid_telephony_usage}
  def terminal(%TelephonyAttempt{} = attempt, outcome, %DateTime{} = observed_at, evidence) do
    with {:ok, measurement} <- connection_duration(attempt, observed_at, evidence),
         {:ok, observation} <-
           build(
             attempt,
             measurement,
             outcome,
             observed_at,
             evidence,
             terminal_component(measurement)
           ) do
      {:ok, [observation]}
    else
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  defp carrier_leg_measurement do
    Measurement.new(
      component: "carrier_legs",
      unit: :requests,
      quantity: 1,
      mode: :delta,
      status: :final,
      provenance: :locally_measured
    )
  end

  defp connection_duration(attempt, ended_at, evidence) do
    case {Keyword.fetch!(evidence, :duration), attempt.connected_at} do
      {:unavailable, _connected_at} ->
        {:ok, nil}

      {:derive, nil} ->
        {:ok, nil}

      {:derive, %DateTime{} = connected_at} ->
        measured_duration(attempt, connected_at, ended_at, evidence)
    end
  end

  defp measured_duration(attempt, connected_at, ended_at, evidence) do
    milliseconds = DateTime.diff(ended_at, connected_at, :millisecond)

    if milliseconds < 0 do
      {:ok, nil}
    else
      Measurement.new(
        component: "connection_duration",
        unit: :milliseconds,
        quantity: milliseconds,
        mode: :cumulative,
        status: :final,
        provenance:
          duration_provenance(
            attempt.connected_provenance,
            Keyword.fetch!(evidence, :provenance)
          )
      )
    end
  end

  defp duration_provenance(:provider_reported, :provider_reported), do: :provider_reported
  defp duration_provenance(_start, _finish), do: :locally_measured

  defp build(attempt, measurement, outcome, observed_at, evidence, component) do
    with {:ok, attribution} <- attribution(attempt) do
      Observation.new(
        id: observation_id(attempt.attempt_id, component),
        delivery_id: Keyword.get(evidence, :delivery_id),
        source_sequence: Keyword.get(evidence, :source_sequence),
        tenant_id: attempt.tenant_id,
        call_id: attempt.call_id,
        attempt_id: attempt.attempt_id,
        capability: :telephony,
        provider: attempt.provider,
        attribution: attribution,
        measurement: measurement,
        outcome: outcome,
        observed_at: observed_at
      )
    end
  end

  defp attribution(attempt) do
    Attribution.new(
      room_id: attempt.room_id,
      incarnation_id: attempt.incarnation_id,
      participant_id: attempt.participant_id,
      leg_id: attempt.attempt_id
    )
  end

  defp terminal_component(%Measurement{component: component}), do: component
  defp terminal_component(nil), do: "terminal"

  defp observation_id(attempt_id, component) do
    digest = :crypto.hash(:sha256, attempt_id <> ":" <> component)
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end
end
