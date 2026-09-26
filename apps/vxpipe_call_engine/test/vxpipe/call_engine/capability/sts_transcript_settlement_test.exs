defmodule Vxpipe.CallEngine.Capability.STSTranscriptSettlementTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Speech.{PrivateInit, Session}
  alias Vxpipe.CallEngine.{SpeechSTSContractProvider, TestAudioOutputSink}

  test "an explicit final waits for both generation and playback" do
    context = start_output()
    assert :ok = transcript(context, "FINAL", true)
    _ = :sys.get_state(context.capability)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    finish_generation(context)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    finish_playback(context)
    assert_transcript(context, "FINAL")
  end

  test "aligned fragments publish only the part whose audio played" do
    context = start_output()
    assert :ok = aligned_transcript(context, "HELLO", 0, 20)
    assert :ok = aligned_transcript(context, " WORLD", 20, 40, true)
    finish_generation(context)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, 20, 40)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)

    capability = context.capability
    turn = context.turn

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent", "HELLO", ^turn, 20, _, _}
  end

  test "an aligned fence reports only the played prefix" do
    context = start_output()
    assert :ok = aligned_transcript(context, "HELLO", 0, 20)
    assert :ok = aligned_transcript(context, " WORLD", 20, 40, true)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, 20, 40)
    assert {:ok, 20} = SpeechToSpeech.interrupt(context.capability)

    capability = context.capability
    turn = context.turn

    assert_receive {:vxpipe_sts_interrupted, ^capability, "agent", ^turn, 20,
                    {:aligned_prefix, "HELLO", _interval}, _}
  end

  test "an aligned fence before playback publishes no prefix" do
    context = start_output()
    assert :ok = aligned_transcript(context, "HELLO", 0, 20, true)
    assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)

    capability = context.capability
    turn = context.turn
    assert_receive {:vxpipe_sts_interrupted, ^capability, "agent", ^turn, 0, :no_prefix, _}
  end

  test "a foreign aligned final cannot finalize the admitted output" do
    context = start_output()
    foreign = %{context | output: make_ref()}
    assert :ok = aligned_transcript(foreign, "FOREIGN", 0, 20, true)
    finish_generation(context)
    finish_playback(context)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    assert :ok = aligned_transcript(context, "CURRENT", 0, 20, true)
    assert_transcript(context, "CURRENT")
  end

  test "aligned transcript fragments have a bounded count" do
    context = start_output()
    capability = context.capability
    monitor = Process.monitor(capability)

    for index <- 1..256 do
      assert :ok = aligned_transcript(context, "A", 0, 20)

      if rem(index, 32) == 0 do
        count =
          Enum.reduce_while(1..500, 0, fn _, _ ->
            %{active_output: %{fragments: fragments}} = :sys.get_state(capability)
            count = length(fragments)
            if count == index, do: {:halt, count}, else: {:cont, count}
          end)

        assert count == index
      end
    end

    # Overflow retires the allocation and can stop the supervised fixture
    # before its synchronous emit call replies.
    try do
      _ = aligned_transcript(context, "B", 20, 40)
    catch
      :exit, _reason -> :ok
    end

    assert_receive {:vxpipe_sts_unavailable, ^capability, :output_text_overflow}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :output_text_overflow}, 1_000
  end

  test "an empty final with no aligned words completes without publishing text" do
    context = start_output()
    assert :ok = transcript(context, "", true)
    finish_generation(context)
    finish_playback(context)
    capability = context.capability
    turn = context.turn
    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^turn, _}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
  end

  test "playback and partial text do not settle before a late explicit final" do
    context = start_output()
    assert :ok = transcript(context, "PARTIAL")
    finish_generation(context)
    finish_playback(context)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
    assert :ok = transcript(context, "FINAL", true)
    assert_transcript(context, "FINAL")
  end

  test "an acknowledged explicit final cannot be replaced by later snapshots" do
    context = start_output()
    assert :ok = transcript(context, "FINAL", true)
    assert :ok = transcript(context, "LATE PARTIAL", false)
    assert :ok = transcript(context, "LATE FINAL", true)
    finish_generation(context)
    finish_playback(context)
    assert_transcript(context, "FINAL")
  end

  test "unrelated turn text cannot finalize the admitted output" do
    context = start_output()
    assert :ok = transcript(%{context | turn: make_ref()}, "FOREIGN", true)
    finish_generation(context)
    finish_playback(context)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
    assert :ok = transcript(context, "CURRENT", true)
    assert_transcript(context, "CURRENT")
  end

  test "missing explicit final times out without publishing partial speech" do
    context = start_output(timeout: 50)
    capability = context.capability
    monitor = Process.monitor(capability)
    assert :ok = transcript(context, "PARTIAL")
    finish_generation(context)
    deadline = :sys.get_state(capability).active_output.text_deadline
    assert is_reference(deadline)
    assert :ok = transcript(context, "UPDATED PARTIAL")
    assert :sys.get_state(capability).active_output.text_deadline == deadline

    assert_receive {:vxpipe_sts_unavailable, ^capability, :output_transcript_timeout}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :output_transcript_timeout}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
  end

  test "generation-boundary text freezes at generation completion" do
    context = start_output(settlement: :generation_boundary)
    assert :ok = transcript(context, "AT BOUNDARY")
    finish_generation(context)
    assert :ok = transcript(context, "TOO LATE")
    finish_playback(context)
    assert_transcript(context, "AT BOUNDARY")
  end

  test "missing generation-boundary text fails at the advertised boundary" do
    context = start_output(settlement: :generation_boundary)
    capability = context.capability
    monitor = Process.monitor(capability)
    finish_generation(context)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :output_transcript_missing}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :output_transcript_missing}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
  end

  test "invalid transcript budgets reject startup without opening an allocation" do
    for timeout <- [nil, 0, -1, 30_001, 5.5, :infinity] do
      sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
      assert {:ok, private} = PrivateInit.open([observer: self()], 5_000)

      assert {:error, reason} =
               start_supervised(
                 {SpeechToSpeech.Tree,
                  owner: self(),
                  agent_id: "invalid-agent",
                  human_id: "caller",
                  provider: {SpeechSTSContractProvider, []},
                  provider_private: private,
                  output_transcript_timeout_ms: timeout,
                  sink: sink},
                 id: make_ref()
               )

      assert inspect(reason) =~ "invalid_output_transcript_timeout"
      refute_received {:vxpipe_sts_ready, _}
    end
  end

  test "a final cancels its deadline while playback is still pending" do
    context = start_output()
    finish_generation(context)
    deadline = :sys.get_state(context.capability).active_output.text_deadline
    assert is_reference(deadline)
    assert :ok = transcript(context, "FINAL", true)
    assert :sys.get_state(context.capability).active_output.text_deadline == nil
    assert Process.read_timer(deadline) == false
    send(context.capability, {:vxpipe_output_transcript_timeout, context.output})
    _ = :sys.get_state(context.capability)
    refute_received {:vxpipe_sts_unavailable, _, _}
    finish_playback(context)
    assert_transcript(context, "FINAL")
  end

  test "deferred sink finish cannot restart the transcript budget or admit a late final" do
    context = start_output(timeout: 25)
    capability = context.capability
    monitor = Process.monitor(capability)
    assert :ok = TestAudioOutputSink.defer_finish(context.sink, true)
    finish_generation(context)

    # The sink has observed generation finalization after its acknowledgement.
    # Let that specific budget elapse while its reply is deliberately withheld.
    timer = make_ref()
    Process.send_after(self(), {:budget_elapsed, timer}, 50)
    assert_receive {:budget_elapsed, ^timer}, 1_000
    assert :ok = transcript(context, "TOO LATE", true)
    assert :ok = TestAudioOutputSink.complete_finish(context.sink)

    assert_receive {:vxpipe_sts_unavailable, ^capability, :output_transcript_timeout}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :output_transcript_timeout}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
  end

  test "late final and timeout from a held output cannot settle its replacement" do
    context = start_output()
    finish_generation(context)
    deadline = :sys.get_state(context.capability).active_output.text_deadline
    assert is_reference(deadline)
    assert :ok = SpeechToSpeech.hold(context.capability)
    assert Process.read_timer(deadline) == false
    assert :ok = SpeechToSpeech.release(context.capability)
    next = open_output(context.capability, context.sink)
    finish_generation(next)
    finish_playback(next)
    send(context.capability, {:vxpipe_output_transcript_timeout, context.output})
    assert :ok = transcript(context, "RETIRED", true)
    _ = :sys.get_state(context.capability)
    refute_received {:vxpipe_sts_unavailable, _, _}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
    assert :ok = transcript(next, "CURRENT", true)
    assert_transcript(next, "CURRENT")
  end

  defp start_output(options \\ []) do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, private} = PrivateInit.open([observer: self()], 5_000)

    tree =
      start_supervised!(
        {SpeechToSpeech.Tree,
         owner: self(),
         agent_id: "agent",
         human_id: "caller",
         provider:
           {SpeechSTSContractProvider,
            [output_settlement: Keyword.get(options, :settlement, :transcript_end)]},
         provider_private: private,
         output_transcript_timeout_ms: Keyword.get(options, :timeout, 5_000),
         sink: sink,
         frame_identity: %{}}
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:vxpipe_sts_ready, ^capability}, 1_000
    open_output(capability, sink)
  end

  defp open_output(capability, sink) do
    provider = Session.provider(:sys.get_state(capability).session)
    turn = make_ref()

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: turn, text: "INPUT", endpointing: :provider_gap]}
             )

    assert_receive {:sts_output_permitted, ^provider, _channel, ^turn, output}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^turn, _}
    assert {:ok, _credit} = GenServer.call(provider, {:output, output})
    assert_receive {:test_audio_output, ^sink, _frame}
    assert_receive {:vxpipe_speech_credit, _, ^output, _, :ok}
    %{capability: capability, provider: provider, turn: turn, output: output, sink: sink}
  end

  defp transcript(context, text, final \\ nil) do
    fields = [turn_ref: context.turn, text: text]
    fields = if is_nil(final), do: fields, else: Keyword.put(fields, :final, final)
    GenServer.call(context.provider, {:emit, :output_transcript, fields})
  end

  defp aligned_transcript(context, text, start_ms, end_ms, final \\ false) do
    GenServer.call(context.provider, {
      :emit,
      :output_transcript,
      [
        turn_ref: context.turn,
        output_ref: context.output,
        text: text,
        audio_start_ms: start_ms,
        audio_end_ms: end_ms,
        final: final
      ]
    })
  end

  defp finish_generation(context) do
    assert :ok =
             GenServer.call(
               context.provider,
               {:emit, :output_completed, [turn_ref: context.turn, request_ref: context.output]}
             )

    sink = context.sink
    assert_receive {:test_audio_output_finish, ^sink, _turn}
  end

  defp finish_playback(context) do
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, 20, 20)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    _ = :sys.get_state(context.capability)
  end

  defp assert_transcript(context, expected) do
    capability = context.capability
    turn = context.turn

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent", ^expected, ^turn, 20, _,
                    _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^turn, _}
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
  end
end
