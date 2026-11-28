defmodule Vxpipe.CallEngine.Speech.SileroRoomIsolationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias CallEngine.CallLoad.{IngressObserver, Room, Runner}
  alias CallEngine.Capability.SpeechToText
  alias CallEngine.Media.AudioFrame
  alias CallEngine.Speech.SileroPoolFixture
  alias Vxpipe.Providers.ElevenLabs.STTSession

  test "closing a room during source replacement preserves the other room's equal-position windows" do
    parent = self()

    classify = fn _, stream, pcm ->
      marker = :binary.first(pcm)

      if marker != 0 do
        send(parent, {:window, marker, stream.samples, self()})
        if marker == 11, do: receive(do: (:finish -> :ok))
      end

      {:ok, stream, [0.0]}
    end

    options =
      SileroPoolFixture.options(__MODULE__, load: fn -> {:ok, :fixture} end, classify: classify)

    observer = start_supervised!(IngressObserver)
    fixture = start_supervised!({CallEngine.Diagnostics.ModelFixture, response: "RECEIVED HI"})
    original = Runner.configure(fixture, observer)
    on_exit(fn -> Runner.restore(original) end)
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      update_in(
        settings[:speech_to_text][:providers][STTSession],
        &Keyword.put(&1, :activity_options, options)
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)

    supervisor =
      start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.Connections})

    first = Room.start(Room.plan(:llm_tts), :llm_tts, supervisor)
    on_exit(fn -> Room.cleanup(first.plan) end)
    second = Room.start(Room.plan(:llm_tts), :llm_tts, supervisor)
    on_exit(fn -> Room.cleanup(second.plan) end)
    refute first.plan.room_id == second.plan.room_id
    first_input = input(first)
    second_input = input(second)

    first_epoch = make_ref()
    second_epoch = make_ref()
    assert :ok = SpeechToText.push_audio(first_input, frame(first, first_epoch, 0, 11))
    assert_receive {:window, 11, 0, worker}
    assert :ok = SpeechToText.push_audio(second_input, frame(second, second_epoch, 0, 22))
    assert :ok = SpeechToText.push_audio(first_input, frame(first, make_ref(), 0, 33))
    assert :ok = SpeechToText.push_audio(second_input, frame(second, second_epoch, 512, 44))
    assert Room.stop(first.root) > 0

    send(worker, :finish)
    assert_receive {:window, 22, 0, ^worker}
    assert_receive {:window, 44, 512, ^worker}
    refute_received {:window, 33, _, _}
    assert :ok = SpeechToText.push_audio(second_input, frame(second, second_epoch, 1024, 55))
    assert_receive {:window, 55, 1024, ^worker}
  end

  defp input(room) do
    connection =
      Map.fetch!(:sys.get_state(room.authority).connections, room.command.connection_id)

    connection.speech_to_text.capability
  end

  defp frame(room, epoch, timestamp, marker) do
    identity =
      Map.take(room.command, [
        :tenant_id,
        :room_id,
        :incarnation_id,
        :participant_id,
        :connection_id
      ])

    struct!(
      AudioFrame,
      Map.merge(identity, %{
        track_id: "load-mic",
        source_epoch: epoch,
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1,
        sequence_number: div(timestamp, 512) + 1,
        timestamp: timestamp,
        received_at: System.monotonic_time(:millisecond),
        payload: :binary.copy(<<marker, 0>>, 512)
      })
    )
  end
end
