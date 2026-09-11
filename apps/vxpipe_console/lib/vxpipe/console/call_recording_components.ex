defmodule Vxpipe.Console.CallRecordingComponents do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Console.CallRecording.Summary

  attr :call_id, :string, required: true
  attr :recordings, :list, required: true
  attr :status, :atom, required: true

  def panel(assigns) do
    ~H"""
    <section class="recording-bay" aria-labelledby="recording-bay-heading">
      <header class="recording-bay-heading">
        <div>
          <h3 id="recording-bay-heading">Recordings</h3>
          <p>Permitted room audio, aligned to its recorded timeline.</p>
        </div>
        <span>{recording_count(@status, @recordings)}</span>
      </header>

      <div :if={@status == :unavailable} class="recording-notice" data-state="unavailable" role="status">
        <strong>Recording evidence unavailable</strong>
        <span>Reload after artifact storage recovers. Live call audio is unaffected.</span>
      </div>

      <div
        :if={@status == :available and @recordings == []}
        class="recording-notice"
        data-state="empty"
        role="status"
      >
        <strong>No recording artifacts</strong>
        <span>This call has no retained audio available to this operator.</span>
      </div>

      <div :if={@status == :available and @recordings != []} class="recording-list">
        <article
          :for={recording <- @recordings}
          class="recording-row"
          data-state={recording_state(recording)}
        >
          <div class="recording-identity">
            <div>
              <strong>{kind_label(recording.kind)}</strong>
              <span class="recording-state" data-state={recording.status}>
                {state_label(recording.status)}
              </span>
            </div>
            <span class="recording-source" title={source_title(recording)}>
              {source_label(recording)}
            </span>
            <span class="recording-id" title={recording.id}>{recording.id}</span>
          </div>

          <dl class="recording-readouts">
            <div><dt>Duration</dt><dd>{duration(recording)}</dd></div>
            <div><dt>Timeline</dt><dd>Starts at {offset(recording)}</dd></div>
            <div><dt>Signal</dt><dd>{signal(recording)}</dd></div>
            <div><dt>Integrity</dt><dd>{integrity(recording)}</dd></div>
          </dl>

          <div class="recording-player">
            <audio
              :if={recording.playable?}
              controls
              preload="metadata"
              src={recording_path(@call_id, recording.id)}
              aria-label={"Play #{kind_label(recording.kind)}"}
            >
              Recording playback is not supported by this browser.
            </audio>
            <div :if={not recording.playable?} class="recording-playback-unavailable" role="status">
              Playback unavailable
            </div>
            <span>{terminal_label(recording.terminal_reason)}</span>
          </div>
        </article>
      </div>
    </section>
    """
  end

  defp recording_count(:unavailable, _recordings), do: "Unavailable"
  defp recording_count(:available, []), do: "No artifacts"
  defp recording_count(:available, [_recording]), do: "1 artifact"
  defp recording_count(:available, recordings), do: "#{length(recordings)} artifacts"

  defp recording_state(%Summary{playable?: false}), do: :unavailable
  defp recording_state(%Summary{status: status}), do: status

  defp kind_label(:full_mix), do: "Full mix"
  defp kind_label(:participant_track), do: "Participant track"

  defp state_label(:complete), do: "Complete"
  defp state_label(:incomplete), do: "Incomplete"

  defp source_label(%Summary{kind: :full_mix}), do: "Room output"
  defp source_label(%Summary{participant_id: participant_id}), do: participant_id

  defp source_title(%Summary{kind: :full_mix}), do: "Room-wide mixed output"

  defp source_title(%Summary{} = recording) do
    Enum.join(
      [recording.participant_id, recording.connection_id, recording.track_id],
      " · "
    )
  end

  defp duration(%Summary{} = recording) do
    seconds(
      recording.ended_offset_samples - recording.started_offset_samples,
      recording.sample_rate
    )
  end

  defp offset(%Summary{} = recording) do
    seconds(recording.started_offset_samples, recording.sample_rate)
  end

  defp seconds(samples, sample_rate) do
    value = samples / sample_rate
    :erlang.float_to_binary(value, decimals: 3) <> " s"
  end

  defp signal(%Summary{} = recording) do
    "#{kilohertz(recording.sample_rate)} · #{channel_label(recording.channels)}"
  end

  defp kilohertz(sample_rate) when rem(sample_rate, 1_000) == 0,
    do: "#{div(sample_rate, 1_000)} kHz"

  defp kilohertz(sample_rate), do: "#{sample_rate} Hz"

  defp channel_label(1), do: "mono"
  defp channel_label(2), do: "stereo"
  defp channel_label(channels), do: "#{channels} channels"

  defp integrity(%Summary{} = recording) do
    "#{count(length(recording.gaps), "gap")} · #{count(recording.rejected_chunks, "rejected chunk")}"
  end

  defp count(1, label), do: "1 #{label}"
  defp count(value, label), do: "#{value} #{label}s"

  defp terminal_label(reason), do: reason |> String.replace("_", " ") |> String.capitalize()

  defp recording_path(call_id, artifact_id) do
    "/calls/#{URI.encode_www_form(call_id)}/recordings/#{URI.encode_www_form(artifact_id)}"
  end
end
