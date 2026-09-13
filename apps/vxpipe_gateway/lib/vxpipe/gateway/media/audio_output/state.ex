defmodule Vxpipe.Gateway.Media.AudioOutput.State do
  @moduledoc false

  @enforce_keys [
    :connection_id,
    :identity,
    :maximum_frames,
    :owner,
    :pipeline,
    :pipeline_options,
    :playback_clearer,
    :pipeline_supervisor,
    :progress_interval_frames
  ]
  defstruct @enforce_keys ++
              [
                current: nil,
                playback_control: nil,
                remote_playback: nil,
                pending_clear: nil,
                delivered_sequence_next: 0,
                in_flight: nil,
                next_sequence_number: 0,
                pending_finish: nil,
                pending_push: nil,
                pipeline_generation: 0,
                pipeline_id: nil,
                pipeline_monitor: nil,
                pipeline_pid: nil,
                pipeline_ready?: false,
                queue: {[], []},
                ready_waiters: [],
                recording_egress: nil,
                remainder: <<>>
              ]

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      connection_id: Keyword.fetch!(options, :connection_id),
      identity: %{
        tenant_id: Keyword.fetch!(options, :tenant_id),
        room_id: Keyword.fetch!(options, :room_id),
        incarnation_id: Keyword.fetch!(options, :incarnation_id),
        participant_id: Keyword.fetch!(options, :participant_id)
      },
      maximum_frames: Keyword.get(options, :maximum_frames, 500),
      owner: Keyword.fetch!(options, :owner),
      pipeline: Keyword.fetch!(options, :pipeline),
      pipeline_options: Keyword.get(options, :pipeline_options, []),
      playback_control: Keyword.get(options, :playback_control),
      playback_clearer:
        Keyword.get(options, :playback_clearer, Vxpipe.Gateway.Media.PlaybackClearer.Noop),
      pipeline_supervisor: Keyword.fetch!(options, :pipeline_supervisor),
      progress_interval_frames: Keyword.get(options, :progress_interval_frames, 5),
      queue: :queue.new()
    }
  end
end
