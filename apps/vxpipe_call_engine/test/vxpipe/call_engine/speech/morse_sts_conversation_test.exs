defmodule Vxpipe.CallEngine.Speech.MorseSTSConversationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  test "one morse input turn yields caller text plus agent reply audio and transcript" do
    session = start_session(provider: MorseSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)

    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, "HI")
    push_chunks(session, pcm)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)
    drain_input_transcripts(session)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "HI"} = ended}

    assert :ok = Session.ack(session, ended)

    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, text: reply} = output_text}

    assert reply == "RECEIVED HI"
    assert output_text.final == true
    assert :ok = Session.ack(session, output_text)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    drain_output_audio(session, output)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = done}
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

  defp push_chunks(session, pcm) do
    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = Session.push_audio(session, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = Session.push_audio(session, tail)
    end
  end

  defp drain_input_transcripts(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = event} ->
        assert :ok = Session.ack(session, event)
        drain_input_transcripts(session)
    after
      100 -> :ok
    end
  end

  defp drain_output_audio(session, output) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        drain_output_audio(session, output)
    after
      100 -> :ok
    end
  end
end
