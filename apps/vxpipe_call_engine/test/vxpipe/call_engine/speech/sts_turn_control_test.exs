defmodule Vxpipe.CallEngine.Speech.STSTurnControlTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}

  test "external mode holds the turn open until the explicit end boundary" do
    session = start_session(options: [turn_control: "external"])
    {:ok, pcm} = morse_pcm("HI")
    push_pcm(session, pcm)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = first}
    assert :ok = Session.ack(session, first)
    drain_transcripts(session)
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}

    assert :ok = Session.input_activity(session, :ended)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "HI"} = ended}

    assert :ok = Session.ack(session, ended)
    assert {:ok, _output} = Session.admit_output(session, ended.turn_ref)
  end

  test "hybrid mode needs both recognition evidence and the explicit end boundary" do
    session = start_session(options: [turn_control: "hybrid"])
    {:ok, pcm} = morse_pcm("HI")
    push_pcm(session, pcm)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    drain_transcripts(session)
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}

    assert :ok = Session.input_activity(session, :ended)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "HI"} = ended}

    assert :ok = Session.ack(session, ended)
  end

  test "provider mode drives turns from recognition without external boundaries" do
    session = start_session(options: [])
    {:ok, pcm} = morse_pcm("HI")
    push_pcm(session, pcm)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    drain_transcripts(session)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "HI"} = ended}

    assert :ok = Session.ack(session, ended)
    assert {:error, :unsupported_operation} = Session.input_activity(session, :started)
  end

  test "transcript source and turn control stay independent selections" do
    assert {:ok, no_output} = MorseSTS.configure(turn_control: "hybrid", output_transcript: false)
    assert no_output.turn_control == "hybrid"
    refute no_output.output_transcript?

    assert {:ok, external} = MorseSTS.configure(turn_control: "external")
    assert external.endpointing == :external
    refute external.speech_start?
  end

  defp start_session(options) do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope), [provider: MorseSTS, owner: self()] ++ options)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready}} = message
    send(self(), message)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    session
  end

  defp morse_pcm(text) do
    {:ok, config} = Config.new([])
    Encoder.encode(config, text)
  end

  defp push_pcm(session, pcm) do
    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = Session.push_audio(session, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = Session.push_audio(session, tail)
    end
  end

  defp drain_transcripts(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = event} ->
        assert :ok = Session.ack(session, event)
        drain_transcripts(session)
    after
      100 -> :ok
    end
  end
end
