defmodule Vxpipe.Providers.ElevenLabs.ScribeTimingTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
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
    {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)

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
    {:ok, replacement} = CaptureHandoff.new(self(), projection: @projection)
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
    {:ok, current} = CaptureHandoff.new(self(), projection: @projection)
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

  defp start_session(options \\ []) do
    {initial?, options} = Keyword.pop(options, :initial_capture, true)
    {wrapped?, options} = Keyword.pop(options, :wrapped, false)

    assert {:ok, handoff} =
             CaptureHandoff.new(self(), Keyword.put(options, :projection, @projection))

    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

    private = [
      config: config,
      wire_module: Wire,
      wire_options: [observer: self()],
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
