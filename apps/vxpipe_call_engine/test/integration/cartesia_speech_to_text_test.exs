defmodule Vxpipe.CallEngine.Integration.CartesiaSpeechToTextTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_cartesia
  @moduletag :capture_log
  @moduletag timeout: 60_000
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Cartesia.{STT, STTSession}
  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.LiveModels

  test "one paced public phrase ends semantically and drains finite input" do
    # Reuse committed public PCM; this test never generates another provider's sample.
    pcm = File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0, 0>>, 16_000 * 4)
    assert byte_size(pcm) <= 16_000 * 2 * 10
    assert rem(byte_size(pcm), 640) == 0

    {:ok, config} =
      STT.new(
        api_key: System.fetch_env!("CARTESIA_API_KEY"),
        model: LiveModels.speech("cartesia", :stt)
      )

    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [model: config.model],
               private: [config: config],
               start_timeout: 15_000
             )

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 15_000
    assert :ok = Session.ack(session, ready)

    for <<frame::binary-size(640) <- pcm>> do
      assert :ok = Session.push_audio(session, frame)
      reference = make_ref()
      Process.send_after(self(), {:audio_pace, reference}, 20)
      assert_receive {:audio_pace, ^reference}, 1_000
    end

    assert :ok = STTSession.finish_input(Session.provider(session))
    turns = collect(session, System.monotonic_time(:millisecond) + 15_000, [], [])

    assert Enum.any?(turns, &(String.downcase(&1) =~ "telescope")),
           "recognition did not preserve the known public phrase's final word"

    assert :ok = Session.close(session)
  end

  defp collect(session, deadline, started, ended) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)

        case event.kind do
          :speech_started ->
            collect(session, deadline, [event.turn_ref | started], ended)

          :turn_ended ->
            assert event.turn_ref in started and event.endpointing == :provider_semantic
            collect(session, deadline, started, [event.text | ended])

          :input_finished ->
            Enum.reverse(ended)

          kind when kind in [:transcript, :eager_turn_ended, :turn_resumed] ->
            assert event.turn_ref in started
            collect(session, deadline, started, ended)
        end

      {:vxpipe_speech_closed, ^session, _safe_reason} ->
        flunk("Cartesia recognition failed before finite completion")
    after
      remaining -> flunk("Cartesia recognition exceeded its bounded drain deadline")
    end
  end
end
