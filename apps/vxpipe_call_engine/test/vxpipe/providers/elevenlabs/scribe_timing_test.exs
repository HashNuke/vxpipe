defmodule Vxpipe.Providers.ElevenLabs.ScribeTimingTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket, STTSession}
  @projection __MODULE__.Projection

  setup do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: @projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :loaded)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(@projection)
    :ok
  end

  test "socket receipt and adapter end emission stay distinct and commits do not end turns" do
    {session, wire, handoff} = start_session()
    socket_frame(session, wire, handoff, "committed_transcript", "private transcript")
    started = event(session, :speech_started)
    _ = event(session, :transcript)

    assert {:provider_landmark, generation, turn, :provider_text_commit, commit_us, 0} =
             packet(handoff)

    assert generation == session.generation
    assert turn == started.turn_ref
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}

    provider = Session.provider(session)
    :sys.suspend(provider)

    try do
      socket_frame(session, wire, handoff, "partial_transcript", "")
      received_by = System.monotonic_time(:microsecond)
      :sys.resume(provider)
      ended = event(session, :turn_ended)
      assert ended.turn_ref == turn
      assert ended.text == "private transcript"

      assert {:provider_landmark, ^generation, ^turn, :provider_end_evidence, receipt_us, 0} =
               packet(handoff)

      assert {:provider_landmark, ^generation, ^turn, :adapter_end_emission, emitted_us, 0} =
               packet(handoff)

      assert commit_us <= receipt_us
      assert receipt_us <= received_by
      assert emitted_us >= received_by
    after
      :sys.resume(provider)
    end
  end

  test "revoked diagnostics preserve normal recognition without collecting landmarks" do
    {session, wire, handoff} = start_session()
    :ok = CaptureHandoff.close(handoff)
    socket_frame(session, wire, handoff, "committed_transcript", "answer")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "answer"
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "saturated diagnostic delivery cannot delay or fail turn settlement" do
    {session, wire, handoff} = start_session(maximum_count: 1)
    socket_frame(session, wire, handoff, "committed_transcript", "answer")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "answer"
    _ = :sys.get_state(Session.provider(session))
    assert %{pending_count: 1, overflow: 2} = CaptureHandoff.stats(handoff)
    assert {:provider_landmark, _, _, :provider_text_commit, _, _} = packet(handoff)
  end

  defp start_session(options \\ []) do
    assert {:ok, handoff} =
             CaptureHandoff.new(self(), Keyword.put(options, :projection, @projection))

    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [commit_strategy: :vad],
               private: [
                 config: config,
                 wire_module: Wire,
                 wire_options: [observer: self()],
                 diagnostic_handoff: handoff
               ]
             )

    assert_receive {:scribe_started, wire}
    Wire.deliver(wire, {:ready, "synthetic"})
    _ = event(session, :ready)
    {session, wire, handoff}
  end

  defp socket_frame(session, wire, handoff, kind, text) do
    # Execute the actual socket callback, then forward its owner message using the
    # allocated wire identity; this fixture does not claim a network exchange.
    state = %{
      owner: self(),
      model: "scribe_v2_realtime",
      commit_strategy: :vad,
      diagnostic_handoff: handoff
    }

    assert {:ok, _} =
             ScribeSocket.handle_frame(
               {:text, JSON.encode!(%{"message_type" => kind, "text" => text})},
               state
             )

    assert_receive {:vxpipe_scribe_transport, _, payload}
    send(Session.provider(session), {:vxpipe_scribe_transport, wire, payload})
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp packet(handoff) do
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    :ok = CaptureHandoff.release(handoff, charge, :processed)
    packet
  end
end
