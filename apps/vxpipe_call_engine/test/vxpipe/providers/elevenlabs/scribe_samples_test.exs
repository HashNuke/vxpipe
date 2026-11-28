defmodule Vxpipe.Providers.ElevenLabs.ScribeSamplesTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

  test "wrapped Scribe maps the next accepted source frame after prospective subscription" do
    {session, wire, handoff} = start_session(initial_capture: false, wrapped: true)
    epoch = make_ref()

    frame = %Vxpipe.CallEngine.Media.AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "inc",
      participant_id: "human",
      connection_id: "connection",
      track_id: "track",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 9_000,
      source_epoch: epoch,
      received_at: System.monotonic_time(:millisecond),
      payload: <<1, 0, 2, 0, 3, 0>>
    }

    assert :ok = Session.push_frame(session, frame)
    assert_receive {:scribe_audio, ^wire, <<1, 0, 2, 0, 3, 0>>}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, _}
    inner = :sys.get_state(Session.provider(session)).inner
    generation = inner.generation

    assert :ok =
             Session.push_frame(session, %{
               frame
               | timestamp: 9_003,
                 sequence_number: 2,
                 payload: <<4, 0, 5, 0>>
             })

    assert_receive {:scribe_audio, ^wire, <<4, 0, 5, 0>>}
    assert {:provider_sample_mapping, ^generation, 3, 9_003} = packet(handoff)
  end

  test "direct continuous input retains one anchor across contiguous frames and same-token subscription" do
    {session, wire, handoff} = start_session()
    first = frame()
    generation = session.generation
    assert :ok = Session.push_frame(session, first)
    assert_receive {:scribe_audio, ^wire, <<1, 0, 2, 0, 3, 0, 4, 0>>}
    assert {:provider_sample_mapping, ^generation, 0, 1_000} = packet(handoff)
    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, _}
    assert :ok = Session.push_frame(session, %{first | timestamp: 1_004, sequence_number: 2})
    assert_receive {:scribe_audio, ^wire, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}

    {:ok, replacement} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    assert :ok = Channel.observe(session, replacement)
    assert_receive {:scribe_observing, ^wire, _}
    refute CaptureHandoff.current?(handoff)
    assert :ok = Session.push_frame(session, %{first | timestamp: 1_008, sequence_number: 3})
    assert_receive {:scribe_audio, ^wire, _}
    assert {:provider_sample_mapping, ^generation, 8, 1_008} = packet(replacement)
  end

  for change <- [
        :raw,
        :duplicate,
        :sequence_gap,
        :timestamp_gap,
        :source_epoch,
        :track,
        :format,
        :invalid_metadata,
        :missing_metadata
      ] do
    test "accepted #{change} retires only diagnostic correspondence" do
      {session, wire, handoff} = start_session()
      first = frame()
      assert :ok = Session.push_frame(session, first)
      assert_receive {:scribe_audio, ^wire, _}
      assert {:provider_sample_mapping, _, 0, 1_000} = packet(handoff)
      next = %{first | timestamp: 1_004, sequence_number: 2}

      changed =
        case unquote(change) do
          :raw -> nil
          :duplicate -> first
          :sequence_gap -> %{next | sequence_number: 3}
          :timestamp_gap -> %{next | timestamp: 1_005}
          :source_epoch -> %{next | source_epoch: make_ref()}
          :track -> %{next | track_id: "other"}
          :format -> %{next | sample_rate: 8_000}
          :invalid_metadata -> %{next | track_id: nil}
          :missing_metadata -> Map.delete(next, :track_id)
        end

      result =
        if changed,
          do: Session.push_frame(session, changed),
          else: Session.push_audio(session, next.payload)

      assert :ok = result
      assert_receive {:scribe_audio, ^wire, <<1, 0, 2, 0, 3, 0, 4, 0>>}
      refute CaptureHandoff.current?(handoff)
      assert :ok = Session.push_audio(session, <<9, 0>>)
      assert_receive {:scribe_audio, ^wire, <<9, 0>>}
      refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    end
  end

  test "revoked and full capture do not reject provider audio" do
    {session, wire, handoff} = start_session(maximum_count: 1)
    assert :ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0})
    assert :ok = Session.push_frame(session, frame())
    assert_receive {:scribe_audio, ^wire, <<1, 0, 2, 0, 3, 0, 4, 0>>}
    refute CaptureHandoff.current?(handoff)
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:reset, _, _, _}, _} = queued
    assert {:error, :revoked} = CaptureHandoff.message(handoff, queued)
    assert :ok = Session.push_frame(session, frame())
    assert_receive {:scribe_audio, ^wire, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "manual Scribe remains a raw-input recognizer while its wrapper accepts frames" do
    assert {:ok, manual} = STTSession.configure(commit_strategy: :manual)
    refute manual.frame_input?

    assert {:ok, wrapper} =
             Vxpipe.CallEngine.Speech.ConversationalSTT.configure(
               provider: STTSession,
               options: [commit_strategy: :manual],
               vad: false
             )

    assert wrapper.frame_input?
  end

  test "VAD reuse still executes one inference for each accepted frame" do
    parent = self()

    classify = fn _model, stream, pcm ->
      send(parent, {:classified, pcm})
      count = div(byte_size(pcm), 1_024)
      {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.0, count)}
    end

    {session, wire, handoff} =
      start_session(
        initial_capture: false,
        wrapped: true,
        vad: true,
        activity_options: [
          load: fn ->
            send(parent, :model_loaded)
            {:ok, :fixture}
          end,
          classify: classify
        ]
      )

    assert_receive :model_loaded
    assert_receive {:classified, warmup}
    assert byte_size(warmup) == 1_024
    assert :ok = Channel.observe(session, handoff)
    assert_receive {:scribe_observing, ^wire, _}
    inner = :sys.get_state(Session.provider(session)).inner
    generation = inner.generation
    pcm = :binary.copy(<<7, 0>>, 512)
    assert :ok = Session.push_frame(session, %{frame() | payload: pcm})
    assert_receive {:scribe_audio, ^wire, ^pcm}
    assert_receive {:classified, ^pcm}

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:provider_sample_mapping, ^generation, 0, 1_000}, _} = message

    assert {:ok, _, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
    refute_received :model_loaded
    refute_received {:classified, _}
  end

  test "a later wire chunk failure never announces an accepted source mapping" do
    {session, wire, _handoff} = start_session(fail_audio_at: 2)
    pcm = :binary.copy(<<1, 0>>, 20_000)

    assert Session.push_frame(session, %{frame() | payload: pcm}) in [
             {:error, :session_failed},
             {:error, :closed}
           ]

    assert_receive {:scribe_audio, ^wire, first}
    assert_receive {:scribe_audio, ^wire, second}
    assert byte_size(first) == 32_000
    assert byte_size(second) == 8_000
    assert first <> second == pcm
    refute_received {:vxpipe_diagnostic_capture, _, _, {:provider_sample_mapping, _, _, _}, _}
  end

  defp frame do
    %Vxpipe.CallEngine.Media.AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "inc",
      participant_id: "human",
      connection_id: "connection",
      track_id: "track",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 1_000,
      source_epoch: make_ref(),
      received_at: System.monotonic_time(:millisecond),
      payload: <<1, 0, 2, 0, 3, 0, 4, 0>>
    }
  end

  defp start_session(options \\ []) do
    {initial?, options} = Keyword.pop(options, :initial_capture, true)
    {wrapped?, options} = Keyword.pop(options, :wrapped, false)
    {vad, options} = Keyword.pop(options, :vad, false)
    {activity_options, options} = Keyword.pop(options, :activity_options, [])
    {fail_audio_at, options} = Keyword.pop(options, :fail_audio_at)

    assert {:ok, handoff} =
             CaptureHandoff.new(
               self(),
               Keyword.put(options, :settings, Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))
             )

    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

    private = [
      config: config,
      wire_module: Wire,
      wire_options: [observer: self(), fail_audio_at: fail_audio_at],
      diagnostic_handoff: if(initial?, do: handoff)
    ]

    provider_options =
      if wrapped? do
        [
          provider: Vxpipe.CallEngine.Speech.ConversationalSTT,
          options: [provider: STTSession, options: [commit_strategy: :vad], vad: vad],
          private: [
            recognizer: STTSession,
            recognizer_options: [commit_strategy: :vad],
            recognizer_private: private,
            activity_options:
              if(vad,
                do:
                  Vxpipe.CallEngine.Speech.SileroPoolFixture.options(__MODULE__, activity_options),
                else: []
              )
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
