defmodule Vxpipe.Providers.ElevenLabs.ScribeTimingTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

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

  test "inbound receipt keeps its sample cursor when a synchronous audio write overlaps" do
    {session, wire, handoff} = start_session()
    assert :ok = Session.push_audio(session, :binary.copy(<<0, 0>>, 320))
    socket_frame(session, wire, handoff, "committed_transcript", "synthetic")
    started = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, 320} = packet(handoff)
    assert turn == started.turn_ref

    payload = JSON.encode!(%{"message_type" => "partial_transcript", "text" => ""})
    assert :ok = GenServer.call(wire, {:next_audio_event, payload})
    # The transport delivers receipt before acknowledging this newer write.
    assert :ok = Session.push_audio(session, :binary.copy(<<0, 0>>, 320))
    _ = event(session, :turn_ended)

    assert {:provider_landmark, ^generation, ^turn, :provider_end_evidence, _, 320} =
             packet(handoff)

    assert {:provider_landmark, ^generation, ^turn, :adapter_end_emission, _, 640} =
             packet(handoff)
  end

  test "explicit draft flush records successful send evidence on the current provider turn" do
    {session, wire, handoff} = start_session()
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    started = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, 0} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 2_000
    assert_receive {:scribe_commit_receipt, ^wire, {token, sent_at}}, 1_000
    assert token == handoff.token
    assert turn == started.turn_ref

    assert {:provider_landmark, ^generation, ^turn, :manual_commit_sent, ^sent_at, 0} =
             packet(handoff)

    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    socket_frame(session, wire, handoff, "committed_transcript", "final draft")
    _ = event(session, :transcript)
    assert {:provider_landmark, ^generation, ^turn, :provider_text_commit, _, 0} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).turn_ref == turn

    assert {:provider_landmark, ^generation, ^turn, :provider_end_evidence, ended_at, 0} =
             packet(handoff)

    assert sent_at <= ended_at
  end

  test "delayed commit replies retain the original send timestamp" do
    {session, wire, handoff} = start_session()
    :ok = GenServer.call(wire, {:commit_mode, :hold})
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, _} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit_receipt, ^wire, {_, sent_at}}, 1_000
    released_at = System.monotonic_time(:microsecond)
    assert :ok = GenServer.call(wire, :release_commit)

    assert {:provider_landmark, ^generation, ^turn, :manual_commit_sent, ^sent_at, 0} =
             packet(handoff)

    assert sent_at <= released_at
  end

  test "revocation during a delayed commit reply suppresses timing without changing the flush" do
    {session, wire, handoff} = start_session()
    :ok = GenServer.call(wire, {:commit_mode, :hold})
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    assert_receive {:scribe_commit_receipt, ^wire, _}, 1_000
    CaptureHandoff.close(handoff)
    assert :ok = GenServer.call(wire, :release_commit)
    socket_frame(session, wire, handoff, "committed_transcript", "final")
    _ = event(session, :transcript)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "first final"
    refute_received {:scribe_commit, ^wire}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "a failed timed send never retries the legacy commit or records success" do
    {session, wire, handoff} = start_session()
    :ok = GenServer.call(wire, {:commit_mode, :fail})
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit_failed, ^wire}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:scribe_commit, ^wire}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "legacy transports still send one commit without inventing send evidence" do
    {session, wire, handoff} = start_session(wire_module: Vxpipe.CallEngine.LegacyScribeTransport)
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    socket_frame(session, wire, handoff, "committed_transcript", "final")
    _ = event(session, :transcript)
    assert {:provider_landmark, _, _, :provider_text_commit, _, _} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "first final"
    assert {:provider_landmark, _, _, :provider_end_evidence, _, _} = packet(handoff)
    assert {:provider_landmark, _, _, :adapter_end_emission, _, _} = packet(handoff)
    refute_received {:scribe_commit, ^wire}
    refute_received {:scribe_commit_receipt, ^wire, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert %{invalid: 0} = CaptureHandoff.stats(handoff)
  end

  test "replacement during a held commit cannot assign its receipt to the new capture" do
    {session, wire, old} = start_session()
    :ok = GenServer.call(wire, {:commit_mode, :hold})
    socket_frame(session, wire, old, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = packet(old)
    socket_frame(session, wire, old, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit_receipt, ^wire, _}, 1_000

    {:ok, current} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    CaptureHandoff.close(old)
    assert :ok = Channel.observe(session, current)
    assert :ok = GenServer.call(wire, :release_commit)
    assert_receive {:scribe_observing, ^wire, token}, 1_000
    assert token == current.token
    socket_frame(session, wire, current, "committed_transcript", "final")
    _ = event(session, :transcript)
    assert {:provider_landmark, _, _, :provider_text_commit, _, _} = packet(current)
    socket_frame(session, wire, current, "partial_transcript", "")
    assert event(session, :turn_ended).text == "first final"
    assert {:provider_landmark, _, _, :provider_end_evidence, _, _} = packet(current)
    assert {:provider_landmark, _, _, :adapter_end_emission, _, _} = packet(current)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
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

  test "an already-running session subscribes prospectively without restarting recognition" do
    {session, wire, handoff} = start_session(initial_capture: false)
    socket_frame(session, wire, nil, "committed_transcript", "before")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    socket_frame(session, wire, nil, "partial_transcript", "")
    _ = event(session, :turn_ended)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}

    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, token}
    assert token == handoff.token
    socket_frame(session, wire, handoff, "committed_transcript", "after")
    started = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, 0} = packet(handoff)
    assert generation == session.generation
    assert turn == started.turn_ref
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "after"

    assert {:provider_landmark, ^generation, ^turn, :provider_end_evidence, _, 0} =
             packet(handoff)

    assert {:provider_landmark, ^generation, ^turn, :adapter_end_emission, _, 0} = packet(handoff)
    refute_received {:scribe_started, _}
  end

  test "VAD wrapper forwards its consumer subscription to a running recognizer" do
    {session, wire, handoff} = start_session(initial_capture: false, wrapped: true)
    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, token}
    assert token == handoff.token
    socket_frame(session, wire, handoff, "committed_transcript", "wrapped")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, 0} = packet(handoff)
    inner = :sys.get_state(Session.provider(session)).inner
    assert generation == inner.generation
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "wrapped"

    assert {:provider_landmark, ^generation, ^turn, :provider_end_evidence, _, 0} =
             packet(handoff)

    assert {:provider_landmark, ^generation, ^turn, :adapter_end_emission, _, 0} = packet(handoff)
    refute_received {:scribe_started, _}
  end

  test "socket subscription accepts only its owner and retains the original capture authority" do
    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    socket = %Vxpipe.CallEngine.Speech.Socket{
      callback_state: %{owner: self(), diagnostic_handoff: nil}
    }

    assert {:noreply, ^socket} =
             Vxpipe.CallEngine.Speech.Socket.handle_info(
               {:diagnostic_socket_observer, Process.whereis(:init), handoff},
               socket
             )

    assert {:noreply, subscribed} =
             Vxpipe.CallEngine.Speech.Socket.handle_info(
               {:diagnostic_socket_observer, self(), handoff},
               socket
             )

    assert subscribed.callback_state.diagnostic_handoff == handoff
    CaptureHandoff.close(handoff)

    assert {:noreply, ^socket} =
             Vxpipe.CallEngine.Speech.Socket.handle_info(
               {:diagnostic_socket_observer, self(), handoff},
               socket
             )
  end

  test "a different consumer and a revoked handle cannot replace the active subscription" do
    {session, wire, handoff} = start_session()

    {:ok, replacement} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    parent = self()

    start_supervised!(
      {Task,
       fn ->
         Channel.observe(session, replacement)
         send(parent, :attempted)
       end}
    )

    assert_receive :attempted
    _ = :sys.get_state(Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    refute_received {:scribe_observing, _, _}
    CaptureHandoff.close(replacement)
    Channel.observe(session, replacement)
    _ = :sys.get_state(Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    refute_received {:scribe_observing, _, _}
    socket_frame(session, wire, handoff, "committed_transcript", "still active")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, _, _, :provider_text_commit, _, 0} = packet(handoff)
  end

  test "replacement revokes old capture and publishes only to the new handle" do
    {session, wire, old} = start_session()

    {:ok, current} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    assert :ok = Channel.observe(session, current)
    assert_receive {:scribe_observing, ^wire, _}
    refute CaptureHandoff.current?(old)
    socket_frame(session, wire, current, "committed_transcript", "new capture")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, _, _, :provider_text_commit, _, 0} = packet(current)
    assert %{pending_count: 0, open?: false} = CaptureHandoff.stats(old)
  end

  test "provider turns link to canonical wrapper turns by references even with identical text" do
    {session, wire, handoff} = start_session(initial_capture: false, wrapped: true)
    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, _}
    inner = :sys.get_state(Session.provider(session)).inner
    inner_generation = inner.generation
    generation = session.generation

    links =
      for _ <- 1..2 do
        socket_frame(session, wire, handoff, "committed_transcript", "same words")
        started = event(session, :speech_started)
        _ = event(session, :transcript)
        canonical = started.turn_ref

        assert_receive {:vxpipe_diagnostic_capture, _, _,
                        {:turn_link, ^inner_generation, native, ^generation, ^canonical}, _} =
                         message

        assert is_reference(native)
        assert native != canonical
        assert {:ok, _, charge} = CaptureHandoff.message(handoff, message)
        CaptureHandoff.release(handoff, charge, :processed)
        socket_frame(session, wire, handoff, "partial_transcript", "")
        assert event(session, :turn_ended).turn_ref == canonical
        _ = :sys.get_state(Session.provider(session))
        refute_received {:vxpipe_diagnostic_capture, _, _, {:turn_link, _, _, _, _}, _}
        {native, canonical}
      end

    assert length(Enum.uniq(links)) == 2
  end

  test "a foreign receipt token cannot invent manual timing or fail a successful flush" do
    {session, wire, handoff} = start_session()
    :ok = GenServer.call(wire, {:commit_mode, :hold})
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit_receipt, ^wire, _}, 1_000

    :sys.replace_state(wire, fn state ->
      Map.update!(state, :held_commit, fn {caller, {_token, at}} ->
        {caller, {make_ref(), at}}
      end)
    end)

    assert :ok = GenServer.call(wire, :release_commit)
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert %{invalid: 0} = CaptureHandoff.stats(handoff)
    socket_frame(session, wire, handoff, "committed_transcript", "final")
    _ = event(session, :transcript)
    assert {:provider_landmark, _, _, :provider_text_commit, _, _} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "first final"
    assert {:provider_landmark, _, _, :provider_end_evidence, _, _} = packet(handoff)
    assert {:provider_landmark, _, _, :adapter_end_emission, _, _} = packet(handoff)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "an unobserved session keeps the ordinary commit path even on a receipt capable transport" do
    {session, wire, handoff} = start_session(initial_capture: false)
    :ok = GenServer.call(wire, {:commit_mode, :fail})
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    refute_received {:scribe_commit_failed, ^wire}
    refute_received {:scribe_commit_receipt, ^wire, _}
    socket_frame(session, wire, handoff, "committed_transcript", "final")
    _ = event(session, :transcript)
    socket_frame(session, wire, handoff, "partial_transcript", "")
    assert event(session, :turn_ended).text == "first final"
    refute_received {:scribe_commit, ^wire}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "manual receipt keeps the current accepted sample prefix" do
    {session, wire, handoff} = start_session()
    audio = :binary.copy(<<1, 0>>, 128)
    assert :ok = Session.push_audio(session, audio)
    assert_receive {:scribe_audio, ^wire, ^audio}
    socket_frame(session, wire, handoff, "committed_transcript", "first")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert {:provider_landmark, generation, turn, :provider_text_commit, _, 128} = packet(handoff)
    socket_frame(session, wire, handoff, "partial_transcript", "draft")
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    assert_receive {:scribe_commit_receipt, ^wire, {_token, at}}, 1_000

    assert {:provider_landmark, ^generation, ^turn, :manual_commit_sent, ^at, 128} =
             packet(handoff)

    refute_received {:scribe_commit, ^wire}
  end

  defp start_session(options \\ []) do
    {wire_module, options} = Keyword.pop(options, :wire_module, Wire)
    {initial?, options} = Keyword.pop(options, :initial_capture, true)
    {wrapped?, options} = Keyword.pop(options, :wrapped, false)

    assert {:ok, handoff} =
             CaptureHandoff.new(
               self(),
               Keyword.put(options, :settings, Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))
             )

    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

    private = [
      config: config,
      wire_module: wire_module,
      wire_options: [observer: self()],
      draft_flush_gap_ms: 10,
      diagnostic_handoff: if(initial?, do: handoff)
    ]

    provider_options =
      if wrapped? do
        [
          provider: Vxpipe.CallEngine.Speech.ConversationalSTT,
          options: [provider: STTSession, options: [commit_strategy: :vad], vad: false],
          private: [
            recognizer: STTSession,
            recognizer_options: [commit_strategy: :vad],
            recognizer_private: private
          ]
        ]
      else
        [provider: STTSession, options: [commit_strategy: :vad], private: private]
      end

    assert {:ok, session, :starting} = Session.start(CapabilityTree.scope(tree), provider_options)

    assert_receive {:scribe_started, wire}
    Wire.deliver(wire, {:ready, "synthetic"})
    _ = event(session, :ready)
    {session, wire, handoff}
  end

  defp socket_frame(_session, wire, _handoff, kind, text) do
    # Run the real callback inside the fixture wire, including its subscription state.
    Wire.deliver_frame(wire, JSON.encode!(%{"message_type" => kind, "text" => text}))
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
    # These helpers inspect timing/probability evidence; links have dedicated assertions.
    case packet do
      {:turn_link, _, _, _, _} -> packet(handoff)
      other -> other
    end
  end
end
