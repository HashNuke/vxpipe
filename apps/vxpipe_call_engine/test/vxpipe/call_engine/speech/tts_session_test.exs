defmodule Vxpipe.CallEngine.Speech.TTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  test "native synthesis delivers credited PCM and one generation completion" do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: MorseSession,
        options: [sample_rate: 8_000, unit_duration_ms: 20]
      )

    assert_receive {:vxpipe_speech, %Event{session: ^allocation, kind: :ready} = ready}, 5_000
    assert :ok = Session.ack(allocation, ready)
    assert {:ok, descriptor} = Session.describe(allocation)
    assert descriptor.kind == :tts
    assert descriptor.format.sample_rate == 8_000

    assert {:ok, %{ref: request}} = Session.speak(allocation, "E")
    {audio, events} = drain(allocation, request, [], [])
    assert Enum.map(events, & &1.kind) == [:input_submitted, :completed]
    assert Enum.all?(events, &(&1.request_ref == request))

    # Independent Morse E: one 20 ms dot, then fourteen units of silence.
    <<dot::binary-size(320), gap::binary>> = audio
    assert byte_size(audio) == 4_800
    assert gap == :binary.copy(<<0, 0>>, 2_240)

    expected =
      for index <- 0..159, into: <<>> do
        sample = round(:math.sin(2.0 * :math.pi() * 700 / 8_000 * index) * 4_096)
        <<sample::signed-little-16>>
      end

    assert dot == expected
    assert :ok = Session.close(allocation)
    refute_received {:vxpipe_speech, %Event{kind: :completed}}
  end

  defp drain(allocation, request, chunks, events) do
    receive do
      {:vxpipe_speech_audio, %{__struct__: Audio, session: ^allocation} = audio} ->
        assert audio.request_ref == request
        assert byte_size(audio.payload) in 1..320
        assert :ok = Session.validate_audio(allocation, audio)
        assert :ok = Session.ack_audio(allocation, audio)
        drain(allocation, request, [audio.payload | chunks], events)

      {:vxpipe_speech, %Event{session: ^allocation} = event} ->
        assert :ok = Session.ack(allocation, event)

        if event.kind == :completed,
          do: {chunks |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse([event | events])},
          else: drain(allocation, request, chunks, [event | events])
    after
      1_000 -> flunk("native TTS did not deliver its next credited result")
    end
  end
end
