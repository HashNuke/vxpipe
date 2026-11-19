defmodule Vxpipe.Calls.LatencyRun do
  @moduledoc "A bounded, versioned diagnostic run for one admitted human audio source."

  @identity_fields [
    :id,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :source_epoch,
    :clock_id
  ]
  @profile_fields [
    :provider,
    :model,
    :commit_strategy,
    :inference_source,
    :vad_model,
    :algorithm_version,
    :sample_rate,
    :onset_threshold,
    :offset_threshold,
    :onset_frames,
    :offset_frames
  ]
  @count_fields [:observed_turns, :dropped_audio_frames, :unmatched_provider_events]
  @reasons [
    :audio_gap,
    :ambiguous_boundary,
    :observer_overloaded,
    :source_changed,
    :partial_start,
    :inference_reset,
    :clock_uncertain,
    :observer_unavailable,
    :unsupported,
    :policy_denied,
    :storage_loss,
    :disabled,
    :call_ended,
    :lease_expired
  ]
  @fields @identity_fields ++
            [
              :schema_version,
              :settings_revision,
              :revision,
              :profile,
              :anchor_utc,
              :heartbeat_at,
              :closed_at,
              :state,
              :counts,
              :reasons
            ]

  @enforce_keys @identity_fields ++ [:settings_revision, :profile, :anchor_utc, :heartbeat_at]
  @derive {Inspect, only: [:id, :revision, :state]}
  defstruct @enforce_keys ++
              [
                schema_version: 1,
                revision: 1,
                state: :running,
                closed_at: nil,
                counts: %{
                  observed_turns: 0,
                  dropped_audio_frames: 0,
                  unmatched_provider_events: 0
                },
                reasons: []
              ]

  def new(attributes) when is_map(attributes) and not is_struct(attributes) do
    with true <- Map.keys(attributes) -- @fields == [],
         attributes = Map.put_new(attributes, :heartbeat_at, Map.get(attributes, :anchor_utc)),
         true <- Enum.all?(@identity_fields, &identifier?(Map.get(attributes, &1))),
         %__MODULE__{} = run <- struct!(__MODULE__, attributes),
         true <- valid?(run) do
      {:ok, run}
    else
      _invalid -> {:error, :invalid_latency_run}
    end
  rescue
    _error -> {:error, :invalid_latency_run}
  end

  def new(_attributes), do: {:error, :invalid_latency_run}

  defp valid?(run) do
    run.schema_version == 1 and positive?(run.revision) and positive?(run.settings_revision) and
      profile?(run.profile) and counts?(run.counts) and reasons?(run.reasons) and timestamps?(run)
  end

  defp timestamps?(run) do
    with %DateTime{} <- run.anchor_utc,
         %DateTime{} <- run.heartbeat_at,
         true <- DateTime.compare(run.heartbeat_at, run.anchor_utc) in [:eq, :gt] do
      case {run.state, run.closed_at} do
        {:running, nil} ->
          true

        {state, %DateTime{} = closed} when state in [:closed, :incomplete] ->
          DateTime.compare(closed, run.heartbeat_at) in [:eq, :gt]

        _invalid ->
          false
      end
    else
      _invalid -> false
    end
  end

  defp profile?(profile) when is_map(profile) and not is_struct(profile) do
    Map.keys(profile) -- @profile_fields == [] and
      Enum.all?([:provider, :model, :vad_model], &identifier?(Map.get(profile, &1))) and
      profile[:commit_strategy] in [:manual, :vad, :provider_semantic, :unknown] and
      profile[:inference_source] in [:operational_reuse, :benchmark_only] and
      positive?(profile[:algorithm_version]) and profile[:sample_rate] == 16_000 and
      threshold?(profile[:onset_threshold]) and threshold?(profile[:offset_threshold]) and
      frames?(profile[:onset_frames]) and frames?(profile[:offset_frames])
  end

  defp profile?(_profile), do: false

  defp counts?(counts) when is_map(counts) and map_size(counts) == 3 do
    Enum.all?(@count_fields, fn key ->
      value = Map.get(counts, key)
      is_integer(value) and value in 0..9_223_372_036_854_775_807
    end)
  end

  defp counts?(_counts), do: false

  defp reasons?(reasons) when is_list(reasons) and length(reasons) <= length(@reasons),
    do: Enum.all?(reasons, &(&1 in @reasons)) and Enum.uniq(reasons) == reasons

  defp reasons?(_reasons), do: false

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp positive?(value), do: is_integer(value) and value in 1..9_223_372_036_854_775_807
  defp threshold?(value), do: is_number(value) and value >= 0 and value <= 1
  defp frames?(value), do: is_integer(value) and value in 1..1_024
end
