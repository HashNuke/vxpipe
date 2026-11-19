defmodule Vxpipe.Calls.TestLatencyRecords do
  alias Vxpipe.Calls.LatencyRun

  def run do
    {:ok, run} =
      LatencyRun.new(%{
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
      })

    run
  end
end
