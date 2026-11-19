defmodule Vxpipe.Calls.LatencyRunTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.LatencyRun

  test "creates a versioned run with explicit source, settings and clock identity" do
    assert {:ok, run} = LatencyRun.new(attributes())
    assert run.state == :running
    assert run.revision == 1

    assert run.counts == %{
             observed_turns: 0,
             dropped_audio_frames: 0,
             unmatched_provider_events: 0
           }

    assert run.profile.inference_source == :benchmark_only
  end

  test "unattached acoustic evidence stays on the run without becoming an observed turn" do
    evidence = %{
      version: 1,
      entries: [
        %{
          epoch: 0,
          start_sample: 0,
          end_sample: 512,
          start_us: 0,
          end_us: 32_000,
          start_confirmed_us: 96_000,
          end_confirmed_us: 544_000,
          uncertainty_us: 100,
          reasons: []
        }
      ],
      omitted_count: 0,
      reasons: []
    }

    assert {:ok, run} = LatencyRun.new(Map.put(attributes(), :unattached_segments, evidence))
    assert run.unattached_segments == evidence
    assert run.counts.observed_turns == 0
    assert {:ok, legacy} = LatencyRun.new(attributes())
    assert legacy.unattached_segments == nil

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(Map.put(attributes(), :unattached_segments, %{evidence | version: 2}))
  end

  test "rejects arbitrary payload/configuration rather than persisting secrets or audio" do
    assert {:error, :invalid_latency_run} =
             LatencyRun.new(Map.put(attributes(), :audio, <<1, 2>>))

    attributes = attributes()
    profile = Map.put(attributes.profile, :api_key, "must-never-be-retained")
    assert {:error, :invalid_latency_run} = LatencyRun.new(%{attributes | profile: profile})
  end

  test "requires enabled settings revision and bounded identities" do
    assert {:error, :invalid_latency_run} = LatencyRun.new(%{attributes() | settings_revision: 0})
    assert {:error, :invalid_latency_run} = LatencyRun.new(%{attributes() | clock_id: ""})

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(%{attributes() | participant_id: String.duplicate("x", 257)})
  end

  test "terminal and heartbeat timestamps cannot precede the run" do
    attrs = attributes()
    before = DateTime.add(attrs.anchor_utc, -1, :second)
    assert {:error, :invalid_latency_run} = LatencyRun.new(Map.put(attrs, :heartbeat_at, before))

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(Map.merge(attrs, %{state: :closed, closed_at: before}))

    assert {:error, :invalid_latency_run} = LatencyRun.new(Map.put(attrs, :state, :closed))

    assert {:ok, _run} =
             LatencyRun.new(
               Map.merge(attrs, %{
                 state: :closed,
                 closed_at: DateTime.add(attrs.anchor_utc, 1, :second)
               })
             )
  end

  test "loss counts and reasons are bounded and do not fabricate completeness" do
    attrs =
      Map.merge(attributes(), %{
        state: :incomplete,
        closed_at: ~U[2026-11-19 12:00:01Z],
        counts: %{observed_turns: 2, dropped_audio_frames: 1, unmatched_provider_events: 0},
        reasons: [:audio_gap]
      })

    assert {:ok, run} = LatencyRun.new(attrs)
    assert run.reasons == [:audio_gap]

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(%{attrs | reasons: ["raw provider response"]})

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(%{attrs | counts: %{observed_turns: -1}})
  end

  test "declared UTC anchors reject non-UTC timestamps" do
    attrs = attributes()
    local = %{attrs.anchor_utc | utc_offset: 3_600, time_zone: "Europe/Paris", zone_abbr: "CET"}
    assert {:error, :invalid_latency_run} = LatencyRun.new(%{attrs | anchor_utc: local})
    assert {:error, :invalid_latency_run} = LatencyRun.new(Map.put(attrs, :heartbeat_at, local))

    assert {:error, :invalid_latency_run} =
             LatencyRun.new(Map.merge(attrs, %{state: :closed, closed_at: local}))
  end

  test "acknowledged provider settings remain distinct from observer settings" do
    attributes = attributes()

    acknowledgement = %{
      model_id: "scribe_v2_realtime",
      sample_rate: 16_000,
      audio_format: "pcm_16000",
      commit_strategy: :vad,
      vad_silence_threshold_secs: 1.5,
      vad_threshold: 0.4,
      min_speech_duration_ms: 100,
      min_silence_duration_ms: 100,
      keepalive_interval_ms: 500
    }

    profile = Map.put(attributes.profile, :provider_acknowledgement, acknowledgement)
    assert {:ok, run} = LatencyRun.new(%{attributes | profile: profile})
    assert run.profile.provider_acknowledgement == acknowledgement
    assert run.profile.onset_threshold == 0.5

    for invalid <- [
          Map.put(acknowledgement, :api_key, "not retained"),
          Map.delete(acknowledgement, :vad_threshold),
          %{acknowledgement | model_id: "other"},
          %{acknowledgement | sample_rate: 16_000.0},
          %{acknowledgement | commit_strategy: :manual},
          %{acknowledgement | vad_threshold: "0.4"},
          %{acknowledgement | vad_silence_threshold_secs: -1},
          %{acknowledgement | keepalive_interval_ms: 0}
        ] do
      assert {:error, :invalid_latency_run} =
               LatencyRun.new(%{
                 attributes
                 | profile: %{profile | provider_acknowledgement: invalid}
               })
    end
  end

  defp attributes do
    %{
      id: "run-1",
      tenant_key: "tenant-1",
      call_id: "call-1",
      room_id: "room-1",
      incarnation_id: "inc-1",
      participant_id: "human-1",
      connection_id: "connection-1",
      source_epoch: "source-1",
      clock_id: "clock-1",
      settings_revision: 1,
      anchor_utc: ~U[2026-11-19 12:00:00Z],
      profile: %{
        provider: "elevenlabs",
        model: "scribe_v2_realtime",
        commit_strategy: :vad,
        inference_source: :benchmark_only,
        vad_model: "silero_v6.2.3",
        algorithm_version: 1,
        sample_rate: 16_000,
        onset_threshold: 0.5,
        offset_threshold: 0.35,
        onset_frames: 4,
        offset_frames: 16
      }
    }
  end
end
