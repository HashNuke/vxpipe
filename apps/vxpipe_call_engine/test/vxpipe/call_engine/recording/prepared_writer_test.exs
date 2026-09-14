defmodule Vxpipe.CallEngine.Recording.PreparedWriterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Recording.{PreparedWriter, Stream}
  alias Vxpipe.CallEngine.TestRecordingWriter

  test "adopts a prepared writer without changing its handle or ending it with the phase" do
    phase = start_supervised!({Agent, fn -> :phase end})
    options = options(phase)
    assert {:ok, prepared} = PreparedWriter.start(TestRecordingWriter, stream(), options)
    assert_receive {:test_recording_writer_opened, source, source, _stream}
    assert source == prepared.source
    assert {:ok, resource, :ready} = TestRecordingWriter.readiness(prepared.handle)
    assert resource.instance == source
    assert :ok = PreparedWriter.adopt(prepared)
    stop_supervised!(Agent)
    assert :ok = PreparedWriter.adopt(prepared)
    assert {:error, :stale_preparation} = PreparedWriter.discard(prepared)
    assert {:ok, ^resource, :ready} = TestRecordingWriter.readiness(prepared.handle)
    monitor = Process.monitor(source)
    assert :ok = PreparedWriter.retire(prepared)
    assert_receive {:DOWN, ^monitor, :process, ^source, :normal}
  end

  for failure <- [:discard, :phase_owner, :recorder, :deadline] do
    @failure failure
    test "#{failure} closes only the newly prepared writer source" do
      phase = start_supervised!({Agent, fn -> :phase end}, id: :phase)
      recorder = start_supervised!({Agent, fn -> :recorder end}, id: :recorder)
      options = options(phase) |> Keyword.put(:source, recorder)

      options =
        if @failure == :deadline,
          do: Keyword.put(options, :deadline_ms, System.monotonic_time(:millisecond) + 200),
          else: options

      assert {:ok, prepared} = PreparedWriter.start(TestRecordingWriter, stream(), options)
      monitor = Process.monitor(prepared.source)
      source = prepared.source

      case @failure do
        :discard -> assert :ok = PreparedWriter.discard(prepared)
        :phase_owner -> stop_supervised!(:phase)
        :recorder -> stop_supervised!(:recorder)
        :deadline -> :ok
      end

      assert_receive {:DOWN, ^monitor, :process, ^source, _reason}, 1_000
      assert {:error, :unavailable} = PreparedWriter.adopt(prepared)
    end
  end

  test "only the recorder can adopt a writer and an expired lease cannot start one" do
    recorder = start_supervised!({Agent, fn -> :recorder end})
    options = options(self()) |> Keyword.put(:source, recorder)
    assert {:ok, prepared} = PreparedWriter.start(TestRecordingWriter, stream(), options)
    assert {:error, :not_owner} = PreparedWriter.adopt(prepared)
    assert :ok = PreparedWriter.discard(prepared)

    assert {:error, :invalid_preparation} =
             PreparedWriter.start(
               TestRecordingWriter,
               stream(),
               Keyword.put(options, :deadline_ms, System.monotonic_time(:millisecond) - 1)
             )
  end

  defp options(phase),
    do: [
      source: self(),
      owner: phase,
      attempt_id: "recording-phase",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000,
      writer_options: [observer: self()]
    ]

  defp stream do
    {:ok, stream} =
      Stream.new(
        %{tenant_id: "tenant", call_id: "call", room_id: "room", incarnation_id: "incarnation"},
        {:individual_track, "caller", "connection", "track"},
        %{sample_rate: 8_000, channels: 1}
      )

    stream
  end
end
