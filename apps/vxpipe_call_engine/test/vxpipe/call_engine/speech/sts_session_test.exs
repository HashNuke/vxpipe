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

  test "STS text input is admitted with its own submission evidence" do
    session = start_session(provider: MorseSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)

    assert :ok = Session.push_text(session, "hello")
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_submitted} = submitted}
    assert :ok = Session.ack(session, submitted)

    assert {:error, :invalid_text} = Session.push_text(session, "")
    assert {:error, :invalid_text} = Session.push_text(session, :bad)
  end

  test "opening is an ordered agent operation with correlated evidence and no caller turn" do
    session = start_session(provider: MorseSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"})

    assert_receive {:vxpipe_speech,
                    %Event{kind: :input_submitted, request_ref: reference} = submitted}

    assert :ok = Session.ack(session, submitted)

    assert_receive {:vxpipe_speech,
                    %Event{kind: :opening_started, request_ref: ^reference, turn_ref: turn} =
                      opening}

    assert :ok = Session.ack(session, opening)
    assert {:ok, _output} = Session.admit_output(session, turn)
    refute_received {:vxpipe_speech, %Event{kind: :input_transcript}}
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    assert {:error, :invalid_opening} = Session.begin_opening(session, {:fixed, ""})
    assert {:error, :invalid_opening} = Session.begin_opening(session, {:fixed, :private})
    assert {:error, :invalid_opening} = Session.begin_opening(session, :unknown)
  end

  test "external turn boundaries are ordered commands unavailable in provider mode" do
    hybrid = start_session(provider: MorseSTS, owner: self(), options: [turn_control: "hybrid"])
    assert_receive {:vxpipe_speech, %Event{session: ^hybrid, kind: :ready} = ready}
    assert :ok = Session.ack(hybrid, ready)
    assert :ok = Session.input_activity(hybrid, :started)
    assert :ok = Session.input_activity(hybrid, :ended)
    assert {:error, :invalid_activity} = Session.input_activity(hybrid, :paused)

    provider_mode = start_session(provider: MorseSTS, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^provider_mode, kind: :ready} = ready}
    assert :ok = Session.ack(provider_mode, ready)

    assert {:error, :unsupported_operation} =
             Session.input_activity(provider_mode, :started)
  end

  test "text and activity commands are rejected on STT allocations" do
    alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: STTSession

    session = start_session(provider: STTSession, owner: self())
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)

    assert {:error, :unsupported_operation} = Session.push_text(session, "hello")
    assert {:error, :unsupported_operation} = Session.input_activity(session, :started)
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
      assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready}} = message, 5_000
      send(self(), message)
    else
      assert_receive {:speech_owner, ^owner,
                      {:vxpipe_speech, %Event{session: ^session, kind: :ready}}},
                     5_000
    end

    session
  end
end
