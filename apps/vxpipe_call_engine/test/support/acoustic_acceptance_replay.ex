defmodule Vxpipe.CallEngine.AcousticAcceptanceReplay do
  @moduledoc "Offline native accuracy paths with frame acknowledgements, never load measurement."
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.CallEngine.Diagnostics.{AttachmentLease, CaptureHandoff}
  alias Vxpipe.CallEngine.Diagnostics.{SourceAdmission, SourceSupervisor, SourceWorker}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, ConversationalSTT}
  alias Vxpipe.CallEngine.Speech.{DiagnosticSubscription, Event, Session}
  alias Vxpipe.CallEngine.Speech.Silero.Model
  alias Vxpipe.CallEngine.SpeechOnsetProbe

  def run(pcm, mode) when mode in [:benchmark_only, :operational_reuse] do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)

    start_supervised!(
      {SourceSupervisor,
       name: __MODULE__.Pool,
       inference: __MODULE__.Inference,
       tasks: __MODULE__.Tasks,
       runtime: __MODULE__.Runtime,
       maximum_sources: 1},
      id: :acoustic_pool
    )

    start_supervised!(
      {DynamicSupervisor, name: __MODULE__.Workers, strategy: :one_for_one},
      id: :acoustic_workers
    )

    admission =
      start_supervised!(
        {SourceAdmission, name: __MODULE__.Admission, gate: AttachmentLease.gate(1)},
        id: :acoustic_admission
      )

    {:ok, lease} = SourceAdmission.reserve(admission, self())

    {:ok, output} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    epoch = make_ref()
    origin = 0

    options = [
      mode: mode,
      attachment_lease: lease,
      owner: self(),
      output: output,
      settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
      source_epoch: epoch,
      clock_id: "offline-acoustic-clock",
      source_id: "caller-stem",
      origin_us: origin,
      clock: fn -> 100_000_000 end
    ]

    assert {:ok, worker} =
             SourceSupervisor.start_input_source(
               options,
               __MODULE__.Workers,
               __MODULE__.Runtime,
               admission
             )

    assert :ok = SourceAdmission.adopt(admission, lease)
    input = SourceWorker.handoff(worker)
    session = start_operational(mode, input)

    # Silence allows endpoint confirmation; neither this tail nor frame padding
    # changes frozen speech bands. Every frame waits for its acoustic progress.
    padded = pcm <> :binary.copy(<<0>>, 32_000)
    padded = padded <> :binary.copy(<<0>>, rem(1_024 - rem(byte_size(padded), 1_024), 1_024))

    packets =
      for(<<chunk::binary-size(1_024) <- padded>>, do: chunk)
      |> Enum.with_index()
      |> Enum.reduce([], fn {chunk, index}, packets ->
        frame = frame(chunk, index, epoch)
        assert :ok = CaptureHandoff.offer(input, {:audio, frame})
        if session, do: assert(:ok = Session.push_frame(session, frame))
        packets = await_progress(output, (index + 1) * 512, packets)
        state = :sys.get_state(worker)
        assert state.boundary.samples == (index + 1) * 512

        if session do
          operational = :sys.get_state(Session.provider(session))
          assert operational.stream.samples == (index + 1) * 512
        else
          assert state.stream.samples == (index + 1) * 512
        end

        packets
      end)
      |> Enum.reverse()

    final_state = :sys.get_state(worker)
    input_stats = CaptureHandoff.stats(input)
    assert input_stats.pending_count == 0
    assert input_stats.overflow == 0
    assert input_stats.discarded == 0
    assert input_stats.invalid == 0
    assert final_state.boundary.samples == div(byte_size(padded), 2)

    if session do
      assert :ok = Session.close(session)
      assert :ok = stop_supervised(:acoustic_tree)
    end

    assert :ok = DynamicSupervisor.terminate_child(__MODULE__.Workers, worker)
    CaptureHandoff.close(output)

    for id <- [:acoustic_admission, :acoustic_workers, :acoustic_pool, :acoustic_settings],
        do: assert(:ok = stop_supervised(id))

    model = Application.app_dir(:vxpipe_call_engine, "priv/speech/#{Model.version()}.onnx")

    %{
      mode: Atom.to_string(mode),
      path:
        if(mode == :benchmark_only,
          do: "SourceWorker native diagnostic inference",
          else: "ConversationalSTT native inference -> InferenceTap -> SourceWorker reuse"
        ),
      completed_samples: final_state.boundary.samples,
      input_capture_stats: input_stats,
      receipt_clock: "synthetic contiguous32ms frame receipt; no wall-clock latency claim",
      appended_silence_samples: div(byte_size(padded) - byte_size(pcm), 2),
      model_version: Model.version(),
      model_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(model)), case: :lower),
      segments: segments(packets),
      resets: packets |> Enum.filter(&match?({:reset, _, _, _}, &1)) |> Enum.map(&json_value/1),
      raw_packets: Enum.map(packets, &json_value/1)
    }
  end

  defp start_operational(:benchmark_only, _input), do: nil

  defp start_operational(:operational_reuse, input) do
    tree = start_supervised!({CapabilityTree, owner: self()}, id: :acoustic_tree)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: ConversationalSTT,
               options: [provider: SpeechOnsetProbe, options: [sample_rate: 16_000], vad: true],
               private: [
                 recognizer: SpeechOnsetProbe,
                 recognizer_options: [sample_rate: 16_000],
                 recognizer_private: [observer: self()]
               ]
             )

    assert_receive {:recognizer, _recognizer, _inner}, 20_000
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    assert :ok = DiagnosticSubscription.request(session, input)
    _ = :sys.get_state(Channel.address(session))
    _ = :sys.get_state(Session.provider(session))
    session
  end

  defp await_progress(output, target, packets) do
    receive do
      {:vxpipe_diagnostic_capture, _, _, _, _} = message ->
        assert {:ok, packet, charge} = CaptureHandoff.message(output, message)
        CaptureHandoff.release(output, charge, :processed)
        packets = [packet | packets]

        case packet do
          {:acoustic_progress, _, _, _finalized_sample} -> packets
          _ -> await_progress(output, target, packets)
        end

      {:vxpipe_speech, %Event{} = event} ->
        assert :ok = Session.ack(event.session, event)
        await_progress(output, target, packets)

      {:recognized_audio, _pcm} ->
        await_progress(output, target, packets)
    after
      20_000 ->
        flunk("missing acoustic progress at sample #{target}; packets=#{inspect(packets)}")
    end
  end

  defp segments(packets) do
    Enum.reduce(packets, [], fn
      {:acoustic_boundary, _, :speech_started, sample, _, _, _, _}, acc ->
        acc ++ [%{onset: sample, end: nil}]

      {:acoustic_boundary, _, :speech_ended, sample, _, _, _, _}, acc ->
        List.update_at(acc, -1, &Map.put(&1, :end, sample))

      _, acc ->
        acc
    end)
  end

  defp json_value(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&json_value/1)

  defp json_value(nil), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value) when is_reference(value), do: "opaque-reference"
  defp json_value(value), do: value

  defp frame(pcm, index, epoch) do
    %AudioFrame{
      tenant_id: "acoustic-fixture",
      room_id: "offline-room",
      incarnation_id: "offline-incarnation",
      participant_id: "human-caller",
      connection_id: "offline-connection",
      track_id: "caller-audio",
      codec: :linear16,
      channels: 1,
      sample_rate: 16_000,
      timestamp: index * 512,
      sequence_number: index + 1,
      received_at: (index + 1) * 32,
      source_epoch: epoch,
      payload: pcm
    }
  end
end
