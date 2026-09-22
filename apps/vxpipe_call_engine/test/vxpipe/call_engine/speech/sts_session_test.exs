defmodule Vxpipe.CallEngine.Speech.STSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionOwner

  test "STS allocation starts, binds, reads ready and admits bounded audio" do
    session = start_session(provider: MorseSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    assert :ok = Session.push_audio(session, <<0, 0>>)
    assert {:error, :invalid_audio} = Session.push_audio(session, :bad)
    assert {:error, :invalid_audio_size} = Session.push_audio(session, <<>>)

    tree = Session.tree(session)
    monitor = Process.monitor(tree)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}
  end

  test "STS descriptor carries turn-control selection and transcript capabilities" do
    assert {:ok, descriptor} = MorseSTS.configure(turn_control: "hybrid")
    assert descriptor.kind == :sts
    assert descriptor.settings.turn_control == "hybrid"
    assert descriptor.speech_start?
    assert descriptor.endpointing in [:provider_semantic, :provider_gap, :external]
  end

  test "owner loss tears down the STS session and provider" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    session = start_session(provider: MorseSTS, owner: owner)
    provider = Session.provider(session)
    tree = Session.tree(session)
    session_monitor = Process.monitor(tree)
    provider_monitor = Process.monitor(provider)
    GenServer.stop(owner)
    assert_receive {:DOWN, ^session_monitor, :process, ^tree, _reason}
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
  end

  defp start_session(options) do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, session, :starting} = Session.start(CapabilityTree.scope(scope), options)
    owner = Keyword.get(options, :owner, self())

    if owner == self() do
      assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready}} = message
      send(self(), message)
    else
      assert_receive {:speech_owner, ^owner,
                      {:vxpipe_speech, %Event{session: ^session, kind: :ready}}}
    end

    session
  end
end
