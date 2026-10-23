defmodule Vxpipe.CallEngine.Integration.MorseCodeApiSTTTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_morse_code_api
  @moduletag :capture_log
  @moduletag timeout: 60_000

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.Providers.MorseCodeApi.{STT, STTSession}

  test "the acknowledged Go profile preserves word gaps and commits repeated independent Morse turns" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = STT.new(api_key: "real socket compatibility key")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [],
               private: [config: config]
             )

    assert event(session, :ready).readiness == :provider_acknowledged
    assert {:ok, profile} = Config.new()
    assert {:ok, pcm} = Encoder.encode(profile, "E E")
    # One dot plus a seven-unit word gap, at 60 ms/unit and 16 kHz S16LE.
    prefix_bytes = div(8 * 60 * 16_000 * 2, 1_000)
    <<prefix::binary-size(prefix_bytes), suffix::binary>> = pcm

    refs =
      for _ <- 1..2 do
        assert :ok = Session.push_audio(session, prefix)
        started = event(session, :speech_started)
        assert event(session, :transcript).text == "E"
        assert :ok = Session.push_audio(session, suffix)
        final = await_final(session, started.turn_ref)
        assert final.text == "E E"
        assert final.endpointing == :provider_gap
        assert final.provider_request_id == started.provider_request_id
        started.turn_ref
      end

    assert length(Enum.uniq(refs)) == 2
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 5_000
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 10_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp await_final(session, turn_ref) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 10_000
    assert event.turn_ref == turn_ref
    assert :ok = Session.ack(session, event)

    case event.kind do
      :transcript -> await_final(session, turn_ref)
      :turn_ended -> event
      other -> flunk("unexpected event during a Morse utterance: #{other}")
    end
  end
end
