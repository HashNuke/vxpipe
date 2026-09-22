defmodule Vxpipe.CallEngine.Speech.STTFinishInputTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTT
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}

  test "finish_input finalizes a fed utterance without duplicating completed turns" do
    session = start_session()
    {:ok, pcm} = morse_pcm("HI")
    push_pcm(session, pcm)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    drain_transcripts(session)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "HI"} = ended}

    assert :ok = Session.ack(session, ended)

    provider = Session.provider(session)
    assert :ok = MorseSTT.finish_input(provider)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_finished} = finished}
    assert :ok = Session.ack(session, finished)
    assert :ok = MorseSTT.finish_input(provider)
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :input_finished}}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}
    assert {:error, :session_failed} = MorseSTT.push_audio(provider, <<0, 0>>)
  end

  test "finish_input is advertised as an optional agent-output STT operation" do
    callbacks = Vxpipe.CallEngine.Speech.STTProvider.behaviour_info(:optional_callbacks)
    assert [finish_input: 1] == callbacks
  end

  test "Morse emits all segments including a flushed tail before one terminal marker" do
    session = start_session()
    {:ok, config} = Config.new([])
    {:ok, first} = Encoder.encode(config, "E")
    {:ok, second} = Encoder.encode(config, "T")

    gap_bytes =
      config.end_gap_units * div(config.sample_rate * config.unit_duration_ms, 1_000) * 2

    tail = binary_part(second, 0, byte_size(second) - gap_bytes)
    push_pcm(session, first <> tail)
    assert :ok = MorseSTT.finish_input(Session.provider(session))

    events = collect_until_finished(session, [])
    assert Enum.filter(events, &(&1.kind == :turn_ended)) |> Enum.map(& &1.text) == ["E", "T"]
    assert List.last(events).kind == :input_finished
    assert Enum.count(events, &(&1.kind == :input_finished)) == 1
  end

  defp collect_until_finished(session, events) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)

    if event.kind == :input_finished,
      do: Enum.reverse([event | events]),
      else: collect_until_finished(session, [event | events])
  end

  defp start_session do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope),
        provider: MorseSTT,
        owner: self()
      )

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
      {:vxpipe_speech, %Event{session: ^session, kind: :transcript} = event} ->
        assert :ok = Session.ack(session, event)
        drain_transcripts(session)
    after
      100 -> :ok
    end
  end
end
