defmodule Vxpipe.Calls.TestLatencyRecords do
  alias Vxpipe.Calls.LatencyRun

  def barge_in do
    %{
      version: 1,
      entries: [
        %{
          output_id: "output-old",
          agent_participant_id: "agent-old",
          response_source_participant_id: "human-old",
          output_connection_id: "connection-old",
          response_turn_id: "turn-old",
          response_command_id: "command-old",
          playback_started_us: 10_000,
          interruption_requested_us: 30_000,
          playback_stopped_us: 45_000,
          speech_started_us: 20_000,
          speech_start_confirmed_us: 60_000,
          speech_start_sample: 320,
          epoch: 1,
          uncertainty_us: 100,
          duration_us: 25_000,
          boundary: :server_egress,
          reasons: []
        }
      ],
      omitted_count: 0,
      reasons: []
    }
  end

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
