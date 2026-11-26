defmodule Vxpipe.Console.Test.LocalRecordingStore do
  @moduledoc "Retains named room and participant tracks as ordinary WAV files during live transfer tests."
  @behaviour Vxpipe.Artifacts.ObjectStore
  @root Path.expand("../../../../tmp/live-telephony", __DIR__)

  def settings do
    run =
      Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S") <>
        "-" <>
        Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

    directory = Path.join(@root, run)
    File.mkdir_p!(@root)
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    IO.puts("Local room recordings: #{directory}")

    [
      enabled: true,
      targets: [:room_track, :individual_tracks],
      maximum_egress_frames: 100,
      maximum_pull_frames: 16,
      writer:
        {Vxpipe.Artifacts.RecordingWriter,
         [
           object_store: __MODULE__,
           object_store_options: [directory: directory],
           maximum_pending_chunks: 100,
           drain_timeout_ms: 30_000
         ]}
    ]
  end

  @impl true
  def open(spec, options) do
    name = Vxpipe.Calls.CallArtifact.track_name(spec)

    with true <-
           Enum.all?(
             [spec.call_id, spec.incarnation_id, spec.artifact_id, name],
             &String.match?(&1, ~r/\A[a-zA-Z0-9_-]+\z/)
           ),
         directory =
           Path.join([Keyword.fetch!(options, :directory), spec.call_id, spec.incarnation_id]),
         :ok <- File.mkdir_p(directory),
         path = Path.join(directory, "#{name}-#{spec.artifact_id}.wav"),
         :ok <- File.write(path, header(spec, 0), [:exclusive]) do
      {:ok, %{path: path, spec: spec, bytes: 0, origin: nil}}
    else
      false -> {:error, :invalid_recording_identity}
      error -> error
    end
  end

  @impl true
  def write_chunk(session, chunk, _options) do
    origin = session.origin || chunk.offset_samples
    offset = (chunk.offset_samples - origin) * session.spec.channels * 2
    bytes = max(session.bytes, offset + byte_size(chunk.payload))

    if offset >= 0 and bytes <= 0xFFFFFFFF - 36 do
      result =
        File.open(session.path, [:read, :write, :binary, :raw], fn file ->
          with :ok <- :file.pwrite(file, 44 + offset, chunk.payload),
               do: :file.pwrite(file, 0, header(session.spec, bytes))
        end)

      case result do
        {:ok, :ok} -> {:ok, %{session | bytes: bytes, origin: origin}}
        {:ok, error} -> error
        error -> error
      end
    else
      {:error, :invalid_wave_offset}
    end
  end

  @impl true
  def complete(session, _manifest, _options), do: {:ok, %{object_key: session.spec.object_key}}

  defp header(spec, bytes) do
    frame = spec.channels * 2

    <<"RIFF", 36 + bytes::little-32, "WAVEfmt ", 16::little-32, 1::little-16,
      spec.channels::little-16, spec.sample_rate::little-32, spec.sample_rate * frame::little-32,
      frame::little-16, 16::little-16, "data", bytes::little-32>>
  end
end
