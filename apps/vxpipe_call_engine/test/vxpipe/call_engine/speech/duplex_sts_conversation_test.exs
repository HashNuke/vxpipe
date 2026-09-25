defmodule Vxpipe.CallEngine.Speech.DuplexSTSConversationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession, as: DuplexSTS

  test "self-yields its reply when caller tone arrives while an output credit is held" do
    session = start_session(provider: DuplexSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)

    push_chunks(session, "HI")
    turn = drain_until_turn_ended(session)

    assert {:ok, output} = Session.admit_output(session, turn)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = held}
    # Hold the credit so the reply stays open, then talk over it.
    push_chunks(session, "NO")
    drain_until_turn_ended(session)

    # The provider finishes the interrupted reply only after the held credit.
    assert :ok = Session.validate_audio(session, held)
    assert :ok = Session.ack_audio(session, held)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, turn_ref: ^turn} =
                      transcript}

    assert :ok = Session.ack(session, transcript)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, turn_ref: ^turn} = done},
                   1_000

    assert :ok = Session.ack(session, done)
    assert :ok = Session.settle_output(session, output, 0)
  end

  defp start_session(options) do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, session, :starting} = Session.start(CapabilityTree.scope(scope), options)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready}} = message, 1_000
    send(self(), message)

    session
  end

  defp push_chunks(session, text) do
    {:ok, pcm} = encode(text)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = Session.push_audio(session, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = Session.push_audio(session, tail)
    end
  end

  defp drain_until_turn_ended(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended, turn_ref: turn} = event} ->
        assert :ok = Session.ack(session, event)
        turn

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        drain_until_turn_ended(session)
    after
      1_000 -> flunk("no turn_ended event")
    end
  end

  defp encode(text) do
    {:ok, config} = Config.new([])
    Encoder.encode(config, text)
  end
end
