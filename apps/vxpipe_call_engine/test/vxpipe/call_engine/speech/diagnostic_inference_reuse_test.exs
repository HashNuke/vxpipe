defmodule Vxpipe.CallEngine.Speech.DiagnosticInferenceReuseTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.CallEngine.SpeechOnsetProbe

  for observing? <- [false, true] do
    @observing observing?
    test "operational inference failure keeps session failure semantics with observation #{@observing}" do
      {session, _recognizer} = session(:fail)
      observer = if @observing, do: handoff()

      if observer do
        assert :ok = ConversationalSTT.observe(session, observer)
        _ = :sys.get_state(Session.provider(session))
      end

      pcm = :binary.copy(<<8, 0>>, 2_048)
      assert :ok = Session.push_audio(session, pcm)
      classifier = first_window(pcm, 0)
      send(classifier, :finish)
      assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000

      if observer do
        assert {:reset, 0, :inference_failed, at} = packet(observer)
        assert is_integer(at)
      else
        refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
      end

      refute_received {:classified, _, _, _}
      refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    end
  end

  test "reuse emits existing probability windows once and disabling never disables operational inference" do
    {session, recognizer} = session(false)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<1, 0>>, 2_048)
    assert :ok = Session.push_audio(session, pcm)
    assert_windows(pcm, 0)
    started = event(session, :speech_started)
    assert {:probabilities, 0, 0, [0.9, 0.9, 0.9, 0.9], timestamp} = window_packets(handoff, 4)
    assert is_integer(timestamp)
    refute_received {:classified, _, _, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}

    :ok = CaptureHandoff.close(handoff)
    assert :ok = Session.push_audio(session, silence())
    assert_windows(silence(), 2_048)
    native = make_ref()

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [turn_ref: native, text: "answer", endpointing: :provider_gap]}
             )

    _ = event(session, :transcript)
    assert event(session, :turn_ended).turn_ref == started.turn_ref
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "revocation during inference preserves its operational result but discards diagnostic evidence" do
    {session, _recognizer} = session(true)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<2, 0>>, 2_048)
    assert :ok = Session.push_audio(session, pcm)
    worker = first_window(pcm, 0)
    :ok = CaptureHandoff.close(handoff)
    send(worker, :finish)
    finish_remaining(pcm, 0)
    _ = event(session, :speech_started)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "mid-inference subscription reports partial coverage and never adopts pre-subscription work" do
    {session, recognizer} = session(true)
    pcm = :binary.copy(<<3, 0>>, 2_048)
    assert :ok = Session.push_audio(session, pcm)
    worker = first_window(pcm, 0)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    assert {:reset, 0, :partial_start, _} = packet(handoff)
    send(worker, :finish)
    finish_remaining(pcm, 0)
    _ = event(session, :speech_started)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert :ok = Session.push_audio(session, silence())
    assert_windows(silence(), 2_048, true)
    _ = :sys.get_state(Session.provider(session))
    # The partially covered epoch still reports nothing until its reset.
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [turn_ref: make_ref(), text: "first", endpointing: :provider_gap]}
             )

    _ = event(session, :transcript)
    _ = event(session, :turn_ended)
    assert {:reset, 1, :provider_turn_settled, _} = packet(handoff)
    assert :ok = Session.push_audio(session, pcm)
    next_worker = first_window(pcm, 0)
    send(next_worker, :finish)
    finish_remaining(pcm, 0)
    _ = event(session, :speech_started)
    assert {:probabilities, 1, 0, [0.9, 0.9, 0.9, 0.9], _} = window_packets(handoff, 4)
  end

  test "an adopted prepared allocation can reuse inference for its current consumer" do
    {session, _recognizer} = session(false, true)
    assert session.consumer == nil
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<4, 0>>, 2_048)
    assert :ok = Session.push_audio(session, pcm)
    assert_windows(pcm, 0)
    _ = event(session, :speech_started)
    assert {:probabilities, 0, 0, [0.9, 0.9, 0.9, 0.9], _} = window_packets(handoff, 4)
  end

  test "a pre-subscription trailing byte makes the diagnostic stream partial" do
    {session, _} = session(false)
    assert :ok = Session.push_audio(session, <<7>>)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    assert {:reset, 0, :partial_start, _} = packet(handoff)
  end

  test "operational reset retaining an odd byte does not claim a clean diagnostic epoch" do
    {session, recognizer} = session(false)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    assert :ok = Session.push_audio(session, <<7>>)

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [turn_ref: make_ref(), text: "first", endpointing: :provider_gap]}
             )

    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = event(session, :turn_ended)
    assert {:reset, 1, :provider_turn_settled, _} = packet(handoff)
    assert {:reset, 1, :partial_start, _} = packet(handoff)
  end

  test "reused probabilities retain absolute source samples across provider resets" do
    {session, recognizer} = session(false)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<5, 0>>, 2_048)

    frame =
      struct(Vxpipe.CallEngine.Media.AudioFrame,
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1,
        timestamp: 32_000,
        payload: pcm
      )

    assert :ok = Session.push_frame(session, frame)
    assert_windows(pcm, 0)
    _ = event(session, :speech_started)

    assert {:mapped_probabilities, 0, 0, 32_000, [0.9, 0.9, 0.9, 0.9], _} =
             window_packets(handoff, 4)

    assert :ok = Session.push_frame(session, %{frame | timestamp: 34_048, payload: silence()})
    assert_windows(silence(), 2_048)
    assert {:mapped_probabilities, 0, 2_048, 34_048, silent, _} = window_packets(handoff, 16)
    assert silent == List.duplicate(0.0, 16)

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [turn_ref: make_ref(), text: "first", endpointing: :provider_gap]}
             )

    _ = event(session, :transcript)
    _ = event(session, :turn_ended)
    assert {:operational_epoch_closed, 0, 32_000, 42_240, _} = packet(handoff)
    assert {:reset, 1, :provider_turn_settled, _} = packet(handoff)
    assert :ok = Session.push_frame(session, %{frame | timestamp: 42_240})
    assert_windows(pcm, 0)
    _ = event(session, :speech_started)

    assert {:mapped_probabilities, 1, 0, 42_240, [0.9, 0.9, 0.9, 0.9], _} =
             window_packets(handoff, 4)

    refute_received {:classified, _, _, _}
  end

  test "a source gap removes mapping without changing operational inference" do
    {session, _recognizer} = session(false)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<6, 0>>, 2_048)

    frame =
      struct(Vxpipe.CallEngine.Media.AudioFrame,
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1,
        timestamp: 32_000,
        payload: pcm
      )

    assert :ok = Session.push_frame(session, frame)
    assert_windows(pcm, 0)
    _ = event(session, :speech_started)
    assert {:mapped_probabilities, 0, 0, 32_000, _, _} = window_packets(handoff, 4)
    assert :ok = Session.push_frame(session, %{frame | timestamp: 40_000})
    assert_windows(pcm, 2_048)
    assert {:reset, 0, :audio_gap, _} = packet(handoff)
    assert {:probabilities, 0, 2_048, _, _} = window_packets(handoff, 4)
    assert :ok = Session.push_frame(session, %{frame | timestamp: 42_048})
    assert_windows(pcm, 4_096)
    assert {:probabilities, 0, 4_096, _, _} = window_packets(handoff, 4)
    refute_received {:classified, _, _, _}
  end

  test "retired inference cannot publish evidence under the new recognition epoch" do
    {session, recognizer} = session(true)
    handoff = handoff()
    assert :ok = ConversationalSTT.observe(session, handoff)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<8, 0>>, 2_048)

    frame =
      struct(Vxpipe.CallEngine.Media.AudioFrame,
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1,
        timestamp: 32_000,
        payload: pcm
      )

    assert :ok = Session.push_frame(session, frame)
    worker = first_window(pcm, 0)

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [turn_ref: make_ref(), text: "first", endpointing: :provider_gap]}
             )

    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = event(session, :turn_ended)
    assert {:operational_epoch_closed, 0, 32_000, 34_048, _} = packet(handoff)
    assert {:reset, 1, :provider_turn_settled, _} = packet(handoff)
    assert :ok = Session.push_frame(session, %{frame | timestamp: 34_048})
    send(worker, :finish)
    refute_received {:vxpipe_diagnostic_capture, _, _, {:mapped_probabilities, 0, _, _, _, _}, _}
    next = first_window(pcm, 0)
    send(next, :finish)
    finish_remaining(pcm, 0)
    _ = event(session, :speech_started)
    assert {:mapped_probabilities, 1, 0, 34_048, _, _} = window_packets(handoff, 4)
    refute_received {:classified, _, _, _}
  end

  test "operational results feed the diagnostic boundary worker without another inference" do
    {session, _recognizer} = session(false)
    output = handoff()
    epoch = make_ref()

    worker =
      start_supervised!(
        {Vxpipe.CallEngine.Diagnostics.SourceWorker,
         mode: :operational_reuse,
         owner: self(),
         output: output,
         settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
         source_epoch: epoch,
         clock_id: "clock",
         source_id: "source",
         origin_us: -1_000_000,
         clock: fn -> 0 end}
      )

    input = Vxpipe.CallEngine.Diagnostics.SourceWorker.handoff(worker)
    assert :ok = ConversationalSTT.observe(session, input)
    _ = :sys.get_state(Session.provider(session))
    pcm = :binary.copy(<<9, 0>>, 2_048)

    frame = %Vxpipe.CallEngine.Media.AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      source_epoch: epoch,
      codec: :linear16,
      channels: 1,
      sample_rate: 16_000,
      timestamp: 32_000,
      sequence_number: 1,
      payload: pcm,
      received_at: -872
    }

    assert :ok = Session.push_frame(session, frame)
    assert :ok = CaptureHandoff.offer(input, {:audio, frame})
    assert_windows(pcm, 0)
    _ = event(session, :speech_started)

    for _ <- 1..3, do: assert({:acoustic_progress, 0, 32_000, 32_000} = packet(output))

    assert {:acoustic_boundary, 0, :speech_started, 32_000, 0, 1_000_000, _, :partial_start} =
             packet(output)

    refute_received {:classified, _, _, _}
    CaptureHandoff.close(output)
    send(worker, :check_grant)
    assert :ok = Session.push_frame(session, %{frame | timestamp: 34_048, sequence_number: 2})
    assert_windows(pcm, 2_048)
  end

  test "VAD onset links a known native hint before any transcript arrives" do
    {session, recognizer} = session(false)
    capture = handoff()
    assert :ok = ConversationalSTT.observe(session, capture)
    _ = :sys.get_state(Vxpipe.CallEngine.Speech.Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    native = make_ref()
    assert :ok = GenServer.call(recognizer, {:emit, :speech_started, [turn_ref: native]})
    _ = :sys.get_state(Vxpipe.CallEngine.Speech.Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    assert :ok = Session.push_audio(session, :binary.copy(<<42, 0>>, 2_048))
    canonical = event(session, :speech_started).turn_ref
    _ = :sys.get_state(Session.provider(session))
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:turn_link, _, ^native, _, ^canonical}, _}
  end

  test "a native hint arriving after VAD onset links the active canonical turn" do
    {session, recognizer} = session(false)
    capture = handoff()
    assert :ok = ConversationalSTT.observe(session, capture)
    _ = :sys.get_state(Vxpipe.CallEngine.Speech.Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    assert :ok = Session.push_audio(session, :binary.copy(<<43, 0>>, 2_048))
    canonical = event(session, :speech_started).turn_ref
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_diagnostic_capture, _, _, {:turn_link, _, _, _, _}, _}
    native = make_ref()
    assert :ok = GenServer.call(recognizer, {:emit, :speech_started, [turn_ref: native]})
    _ = :sys.get_state(Vxpipe.CallEngine.Speech.Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:turn_link, _, ^native, _, ^canonical}, _}
  end

  defp session(hold?, prepared? \\ false) do
    parent = self()

    classify = fn _model, stream, audio ->
      if audio != :binary.copy(<<0>>, 1_024) or stream.samples > 0 do
        send(parent, {:classified, self(), stream.samples, audio})

        if hold? in [true, :fail],
          do:
            (receive do
               :finish -> :ok
             end)
      end

      if hold? == :fail and audio != :binary.copy(<<0>>, 1_024) do
        {:error, :fixture_inference_failed}
      else
        count = div(byte_size(audio), 1_024)
        probability = if :binary.first(audio) == 0, do: 0.0, else: 0.9

        {:ok, %{stream | samples: stream.samples + count * 512},
         List.duplicate(probability, count)}
      end
    end

    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               consumer: if(prepared?, do: nil, else: self()),
               lease: if(prepared?, do: self(), else: nil),
               provider: ConversationalSTT,
               options: [provider: SpeechOnsetProbe, options: [sample_rate: 16_000], vad: true],
               private: [
                 # Local VAD ends turns: a 1 ms resume window after silence, then
                 # the recognizer final settles the turn.
                 endpoint_hangover_ms: 1,
                 final_wait_ms: 10_000,
                 recognizer: SpeechOnsetProbe,
                 recognizer_options: [sample_rate: 16_000],
                 recognizer_private: [observer: self()],
                 activity_options:
                   Vxpipe.CallEngine.Speech.SileroPoolFixture.options(__MODULE__,
                     load: fn -> {:ok, :model} end,
                     classify: classify
                   )
               ]
             )

    assert_receive {:recognizer, recognizer, _}

    if prepared? do
      assert_receive {:vxpipe_speech_prepared, ^session, _}, 1_000
      assert :ok = Session.adopt(session, self())
    end

    _ = event(session, :ready)
    {session, recognizer}
  end

  defp silence, do: :binary.copy(<<0, 0>>, 8_192)

  defp handoff do
    assert {:ok, handoff} =
             CaptureHandoff.new(self(),
               settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__)
             )

    handoff
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp first_window(<<frame::binary-size(1024), _::binary>>, offset) do
    assert_receive {:classified, worker, ^offset, ^frame}
    worker
  end

  defp finish_remaining(<<_first::binary-size(1024), rest::binary>>, offset) do
    assert_windows(rest, offset + 512, true)
  end

  defp assert_windows(audio, offset, finish? \\ false) do
    for <<window::binary-size(1024) <- audio>>, reduce: offset do
      sample ->
        assert_receive {:classified, worker, ^sample, ^window}
        if finish?, do: send(worker, :finish)
        sample + 512
    end
  end

  defp window_packets(handoff, count) do
    first = packet(handoff)

    {tag, epoch, offset, source, p, at} =
      case first do
        {:mapped_probabilities, epoch, offset, source, [p], at} ->
          {:mapped_probabilities, epoch, offset, source, p, at}

        {:probabilities, epoch, offset, [p], at} ->
          {:probabilities, epoch, offset, nil, p, at}
      end

    rest =
      for index <- 1..(count - 1) do
        expected = offset + 512 * index

        if source do
          absolute = source + 512 * index
          assert {^tag, ^epoch, ^expected, ^absolute, [score], _} = packet(handoff)
          score
        else
          assert {^tag, ^epoch, ^expected, [score], _} = packet(handoff)
          score
        end
      end

    if source,
      do: {tag, epoch, offset, source, [p | rest], at},
      else: {tag, epoch, offset, [p | rest], at}
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
