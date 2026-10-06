defmodule Vxpipe.CallEngine.Capability.SpeechToSpeechOutputSTTTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.TestAudioOutputSink

  @human "human1"
  @agent "agent1"

  test "multiple final segments publish once only after finite-input completion" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [observer: self()]
      )

    assert_receive {:output_stt_started, recognizer}
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    complete_playback(20)

    first = make_ref()

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :transcript, [turn_ref: first, text: "FIRST DRAFT"]}
             )

    assert :ok =
             GenServer.call(recognizer, {:emit, :transcript, [turn_ref: first, text: "FIRST"]})

    assert :ok = emit_segment(recognizer, first, "FIRST")
    refute_receive {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, ^capability, _, _, _}
    assert :ok = emit_segment(recognizer, first, "FIRST")
    assert :ok = emit_segment(recognizer, make_ref(), "SECOND")
    assert :ok = GenServer.call(recognizer, {:emit, :input_finished, []})

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "FIRST SECOND", ^turn, 20,
                    _, _},
                   1_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
  end

  test "successful finite recognition retires ONE before accepting TWO and ignores old endpoints" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [observer: self()]
      )

    assert_receive {:output_stt_started, recognizer}
    original = :sys.get_state(capability).output_stt.session
    monitor = Process.monitor(recognizer)
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first, _}
    complete_playback(20)
    assert :ok = emit_segment(recognizer, make_ref(), "ONE")
    assert :ok = GenServer.call(recognizer, {:emit, :input_finished, []})

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "ONE", ^first, _, _, _},
                   1_000

    assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000
    assert_receive {:output_stt_started, replacement}, 1_000
    assert :ok = SpeechToSpeech.push_text(capability, "TWO")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, second, _}, 1_000

    send(
      capability,
      {:vxpipe_speech,
       %Vxpipe.CallEngine.Speech.Event{
         session: original,
         kind: :turn_ended,
         sequence: 99,
         text: "DELAYED ONE"
       }}
    )

    assert :ok = emit_segment(replacement, make_ref(), "TWO")
    complete_playback(20)
    refute_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, _, ^second, _, _, _}
    assert :ok = GenServer.call(replacement, {:emit, :input_finished, []})

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "TWO", ^second, _, _, _},
                   1_000
  end

  defp emit_segment(recognizer, reference, text) do
    GenServer.call(
      recognizer,
      {:emit, :turn_ended, [text: text, turn_ref: reference, endpointing: :provider_gap]}
    )
  end

  test "recognition readiness preserves every pending reply in order" do
    {_tree, capability, _sink} = start_deferred_output_stt()
    assert_receive {:output_stt_waiting, recognizer}

    turns =
      for text <- ["ONE", "TWO", "THREE"] do
        assert :ok = SpeechToSpeech.push_text(capability, text)

        assert_receive {:vxpipe_sts_input_event, ^capability,
                        %{
                          event: %{
                            kind: :input_transcript,
                            text: ^text,
                            turn_ref: turn,
                            final: true
                          }
                        }}

        turn
      end

    Enum.reduce(turns, recognizer, fn turn, current ->
      assert :ok = Vxpipe.CallEngine.SpeechOutputSTTSlowProvider.release_ready(current)
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn, _}, 1_000
      complete_playback(20)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 1_000
      assert_receive {:output_stt_waiting, replacement}, 1_000
      replacement
    end)
  end

  test "pending reply overflow fails the allocation instead of growing without bound" do
    {tree, capability, _sink} = start_deferred_output_stt()
    monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    assert_receive {:output_stt_waiting, _recognizer}

    for _ <- 1..17 do
      assert :ok = SpeechToSpeech.push_text(capability, "HI")

      assert_receive {:vxpipe_sts_input_event, ^capability,
                      %{event: %{kind: :input_transcript, text: "HI", final: true}}}
    end

    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_turn_overflow}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :pending_turn_overflow}, 1_000
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 1_000
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
  end

  defp start_deferred_output_stt do
    start_output_stt_capability(
      policy: unrestricted(),
      output_stt: {Vxpipe.CallEngine.SpeechOutputSTTSlowProvider, []},
      output_stt_private: [ready_observer: self()]
    )
  end

  test "output STT yields one agent transcript and never a caller transcript" do
    {_tree, capability, _sink} = start_output_stt_capability(policy: unrestricted())

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      identity: %{participant_id: @human},
                      event: %{kind: :input_transcript, text: "HI"}
                    }}

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _turn, 20,
                    _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
    refute_received {:vxpipe_sts_input_event, ^capability, %{identity: %{participant_id: @agent}}}
  end

  test "denied transcript policy settles the turn without agent text" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: deny_transcript(@agent, @human))

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}
  end

  test "output STT failure at finalization settles honestly without agent text" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTFailingProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}
  end

  test "output STT loss still settles and the next turn recovers" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: unrestricted(), output_stt_timeout_ms: 300)

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}

    capability_monitor = Process.monitor(capability)

    provider =
      :sys.get_state(capability)
      |> Map.fetch!(:output_stt)
      |> Map.fetch!(:session)
      |> Session.provider()

    provider_monitor = Process.monitor(provider)
    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, :killed}

    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 5_000

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn2, _}, 5_000
    assert turn2 != turn
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn2, 20,
                    _interval, _},
                   5_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn2, _}
    refute_received {:DOWN, ^capability_monitor, :process, ^capability, _}
  end

  test "settled output-STT turns attribute both the STS and recognition legs" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
    assert_receive {:vxpipe_usage_observations, ^capability, observations}

    assert Enum.map(observations, & &1.capability) |> Enum.sort() == [
             :output_speech_to_text,
             :speech_to_speech
           ]

    assert Enum.all?(observations, &(&1.outcome == :succeeded))
    assert Enum.all?(observations, &(&1.attribution.participant_id == @agent))
  end

  for field <- [:provider, :duration, :outcome] do
    test "timed-out recognition reports its own #{field} independently of successful playback" do
      {_tree, capability, _sink} =
        start_output_stt_capability(
          policy: unrestricted(),
          usage_context: sts_usage_context(),
          output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
          output_stt_timeout_ms: 100
        )

      assert :ok = SpeechToSpeech.push_text(capability, "ONE")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
      complete_playback(20)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 2_000
      assert_receive {:vxpipe_usage_observations, ^capability, observations}
      sts = Enum.find(observations, &(&1.capability == :speech_to_speech))
      stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
      assert sts.outcome == :succeeded
      assert sts.provider.integration_id == "local-sts"

      case unquote(field) do
        :provider ->
          assert stt.provider.name == "stalling_stt"
          assert stt.provider.model == "stalling_stt"
          assert stt.provider.integration_id == nil

        :duration ->
          {:ok, config} = Config.new([])
          {:ok, pcm} = Encoder.encode(config, "RECEIVED ONE")
          assert stt.measurement.quantity == div(byte_size(pcm) * 1_000, 16_000 * 2)
          assert stt.measurement.provenance == :locally_measured

        :outcome ->
          assert stt.outcome == :failed
      end

      refute_received {:vxpipe_usage_observations, ^capability, _}
    end
  end

  for rate <- [8_000, 24_000] do
    test "successful recognition uses the selected #{rate} Hz PCM rate" do
      {_tree, capability, _sink} =
        start_output_stt_capability(
          policy: unrestricted(),
          usage_context: sts_usage_context(),
          provider_options: [sample_rate: unquote(rate)],
          output_stt: {Vxpipe.Providers.MorseCode.STTSession, [sample_rate: unquote(rate)]}
        )

      assert :ok = SpeechToSpeech.push_text(capability, "HI")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
      complete_playback(20)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
      assert_receive {:vxpipe_usage_observations, ^capability, observations}
      stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
      {:ok, config} = Config.new(sample_rate: unquote(rate))
      {:ok, pcm} = Encoder.encode(config, "RECEIVED HI")
      assert stt.measurement.quantity == div(byte_size(pcm) * 1_000, unquote(rate) * 2)
      assert stt.outcome == :succeeded
    end
  end

  test "a rejected recognition finalization does not inherit playback success" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [finish_error: :rejected_finalization]
      )

    assert :ok = SpeechToSpeech.push_text(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
    assert_receive {:vxpipe_usage_observations, ^capability, observations}
    stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
    assert stt.outcome == :failed
  end

  test "interruption cancels unfinished recognition without discarding accepted duration" do
    {_tree, capability, sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []}
      )

    assert :ok = SpeechToSpeech.push_text(capability, "HI")
    assert_receive {:test_audio_output_finish, ^sink, _}, 5_000
    assert {:ok, 0} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_usage_observations, ^capability, observations}
    stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
    assert stt.outcome == :cancelled
    assert stt.provider.name == "stalling_stt"
    assert stt.measurement.quantity == 5_700
    refute_received {:vxpipe_usage_observations, ^capability, _}
  end

  test "rejected recognition chunks are excluded and cannot yield successful usage" do
    {_tree, capability, sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTSlowProvider, []}
      )

    assert :ok = SpeechToSpeech.push_text(capability, "HI")
    # The controlled recognizer rejects exactly the first two PCM submissions.
    assert_receive {:test_audio_output, ^sink, first}, 5_000
    assert_receive {:test_audio_output, ^sink, second}, 5_000
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _, _}
    assert_receive {:vxpipe_usage_observations, ^capability, observations}
    stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, "RECEIVED HI")
    accepted_bytes = byte_size(pcm) - byte_size(first.payload) - byte_size(second.payload)
    assert stt.measurement.quantity == div(accepted_bytes * 1_000, 16_000 * 2)
    assert stt.outcome == :failed
  end

  test "idle replacement loss after finite recognition preserves successful usage" do
    {_tree, capability, sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [observer: self()]
      )

    assert_receive {:output_stt_started, recognizer}
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:test_audio_output_finish, ^sink, _}, 5_000

    pending = :sys.get_state(capability).active_output
    assert pending.generation_done?
    refute pending.playback_done?
    assert pending.text_deadline == nil
    assert pending.text_expires_at == nil

    assert :ok =
             GenServer.call(
               recognizer,
               {:emit, :turn_ended,
                [text: "RECEIVED ONE", turn_ref: make_ref(), endpointing: :provider_gap]}
             )

    monitor = Process.monitor(recognizer)
    assert :ok = GenServer.call(recognizer, {:emit, :input_finished, []})
    assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000
    assert_receive {:output_stt_started, replacement}, 1_000
    before_loss = :sys.get_state(capability)
    assert before_loss.active_output.generation_done?
    assert before_loss.active_output.stt_outcome == :succeeded
    monitor = Process.monitor(replacement)
    Process.exit(replacement, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, :killed}
    assert_receive {:output_stt_started, next}, 5_000
    refute next == replacement
    _ = :sys.get_state(capability)

    :ok = TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_usage_observations, ^capability, observations}, 5_000
    stt = Enum.find(observations, &(&1.capability == :output_speech_to_text))
    assert stt.measurement.quantity == 6_300
    assert stt.outcome == :succeeded

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED ONE", _, 20, _,
                    _}

    refute_received {:vxpipe_usage_observations, ^capability, _}
  end

  test "output STT finalization errors are explicit instead of silent" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTFailingProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 5_000
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, _reason}, 5_000
  end

  test "missing output-STT text settles explicitly after the recognition deadline" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_timeout_ms: 100
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 2_000
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, :timeout}, 2_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
  end

  test "a final segment without input_finished still fails at the recognition deadline" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [observer: self()],
        output_stt_timeout_ms: 100
      )

    assert_receive {:output_stt_started, recognizer}
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert :ok = emit_segment(recognizer, make_ref(), "NOT COMPLETE")
    complete_playback(20)
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, :timeout}, 2_000
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 2_000
    assert_receive {:vxpipe_usage_observations, ^capability, observations}
    assert Enum.find(observations, &(&1.capability == :output_speech_to_text)).outcome == :failed
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
  end

  @tag :recognition_deadline_race
  test "queued terminal proof processed after absolute recognition expiry cannot succeed" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        usage_context: sts_usage_context(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [observer: self()],
        output_stt_timeout_ms: 500
      )

    assert_receive {:output_stt_started, recognizer}
    monitor = Process.monitor(recognizer)
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    complete_playback(20)
    assert :ok = emit_segment(recognizer, make_ref(), "LATE FINAL")
    output = :sys.get_state(capability).active_output
    assert output.generation_done? and output.playback_done?

    assert Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputRecognition.text(output.stt_segments) ==
             "LATE FINAL"

    timer = output.text_deadline
    assert is_reference(timer)
    assert :ok = :sys.suspend(capability)

    try do
      assert :ok = GenServer.call(recognizer, {:emit, :input_finished, []})
      remaining = Process.read_timer(timer)
      assert is_integer(remaining) and remaining > 0
      token = make_ref()
      Process.send_after(self(), {:recognition_budget_elapsed, token}, remaining + 50)
      assert_receive {:recognition_budget_elapsed, ^token}, 1_500
    after
      :ok = :sys.resume(capability)
    end

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 1_000
    assert_receive {:vxpipe_usage_observations, ^capability, observations}, 1_000
    assert Enum.find(observations, &(&1.capability == :output_speech_to_text)).outcome == :failed
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, :timeout}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, ^capability, _, _, _}
    refute_received {:vxpipe_usage_observations, ^capability, _}
  end

  for failure <- [:conflicting_final, :recognition_overflow] do
    test "#{failure} fails recognition without publishing a partial aggregate" do
      {_tree, capability, _sink} =
        start_output_stt_capability(
          policy: unrestricted(),
          output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
          output_stt_private: [observer: self()]
        )

      assert_receive {:output_stt_started, recognizer}
      monitor = Process.monitor(recognizer)
      assert :ok = SpeechToSpeech.push_text(capability, "ONE")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
      complete_playback(20)
      ref = make_ref()

      text =
        if unquote(failure) == :recognition_overflow,
          do: String.duplicate("x", 65_536),
          else: "FIRST"

      assert :ok = emit_segment(recognizer, ref, text)
      next_ref = if unquote(failure) == :recognition_overflow, do: make_ref(), else: ref
      # The terminal event may retire its producer before a synchronous reply returns.
      GenServer.cast(
        recognizer,
        {:emit, :turn_ended, [text: "SECOND", turn_ref: next_ref, endpointing: :provider_gap]}
      )

      assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, unquote(failure)}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 1_000
      refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
    end
  end

  for failure <- [:timeout, :finalization_error] do
    test "#{failure} retires a still-live recognizer before the next reply" do
      private =
        if unquote(failure) == :finalization_error,
          do: [finish_error: :rejected_finalization],
          else: []

      {_tree, capability, _sink} =
        start_output_stt_capability(
          policy: unrestricted(),
          output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
          output_stt_private: Keyword.put(private, :observer, self()),
          output_stt_timeout_ms: 100
        )

      assert_receive {:output_stt_started, recognizer}
      original = :sys.get_state(capability).output_stt.session
      assert Session.provider(original) == recognizer
      monitor = Process.monitor(recognizer)
      assert :ok = SpeechToSpeech.push_text(capability, "ONE")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first, _}
      complete_playback(20)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^first, _}, 2_000
      assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, _}, 2_000
      assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000

      assert_receive {:output_stt_started, replacement_provider}, 1_000
      assert :ok = GenServer.call(replacement_provider, {:finish_error, nil})

      assert :ok = SpeechToSpeech.push_text(capability, "TWO")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, second, _}, 2_000
      replacement = :sys.get_state(capability).output_stt.session
      refute replacement == original
      # An already-forwarded retired-generation endpoint must also be inert.
      send(
        capability,
        {:vxpipe_speech,
         %Vxpipe.CallEngine.Speech.Event{
           session: original,
           kind: :turn_ended,
           sequence: 99,
           text: "OLD FIRST REPLY"
         }}
      )

      provider = Session.provider(replacement)
      assert provider == replacement_provider

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :turn_ended,
                  [text: "CURRENT SECOND REPLY", turn_ref: make_ref(), endpointing: :provider_gap]}
               )

      complete_playback(20)

      assert :ok = GenServer.call(provider, {:emit, :input_finished, []})

      assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "CURRENT SECOND REPLY",
                      ^second, _, _, _},
                     2_000

      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^second, _}, 2_000

      refute_received {:vxpipe_sts_agent_transcript, ^capability, @agent, "OLD FIRST REPLY", _, _,
                       _, _}
    end
  end

  test "output-STT audio arriving before recognition readiness is buffered, not dropped" do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output, as: STS

    {_tree, capability, _sink} = start_output_stt_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}

    state = :sys.get_state(capability)
    assert state.output_stt.ready? == true

    suspended = put_in(state.output_stt.ready?, false)

    buffered =
      Enum.reduce(1..16, suspended, fn i, state ->
        STS.buffer_output_audio(state, <<i, 0>>)
      end)

    assert length(buffered.output_stt.pending_audio) == 16
    assert buffered.output_stt.dropped_chunks == suspended.output_stt.dropped_chunks

    overflowed = STS.buffer_output_audio(buffered, <<17, 0>>)
    assert length(overflowed.output_stt.pending_audio) == 16
    assert overflowed.output_stt.dropped_chunks == suspended.output_stt.dropped_chunks + 1
  end

  test "exhausted recognizer recovery ends the allocation without transcript-source fallback" do
    counter = start_supervised!({Agent, fn -> 0 end})

    {tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
        output_stt_private: [start_counter: counter],
        output_stt_timeout_ms: 100
      )

    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first, _}
    assert :ok = SpeechToSpeech.push_text(capability, "TWO")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "TWO", turn_ref: second}}}

    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^first, _}, 2_000
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, :restart_failed}, 4_000

    assert_receive {:DOWN, ^capability_monitor, :process, ^capability,
                    :output_stt_restart_failed},
                   1_000

    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}, 1_000
    assert Agent.get(counter, & &1) in 2..11
    refute_received {:vxpipe_sts_turn_started, ^capability, @agent, ^second, _}
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
  end

  test "a slow output STT consumer cannot block sink audio" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTSlowProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "SLOW RESULT", _, _,
                    _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}

    drops = :sys.get_state(capability) |> Map.fetch!(:output_stt) |> Map.fetch!(:dropped_chunks)
    assert drops == 2
  end

  defp start_output_stt_capability(options) do
    output_stt =
      Keyword.get(options, :output_stt, {Vxpipe.Providers.MorseCode.STTSession, []})

    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
    {:ok, private_init} = PrivateInit.open([], 5_000)
    {:ok, output_private} = PrivateInit.open(Keyword.get(options, :output_stt_private, []), 5_000)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: self(),
             agent_id: @agent,
             human_id: @human,
             provider:
               {Vxpipe.Providers.MorseCode.STSSession,
                Keyword.put(
                  Keyword.get(options, :provider_options, []),
                  :output_transcript,
                  false
                )},
             provider_private: private_init,
             output_stt: output_stt,
             output_stt_private: output_private,
             sink: sink,
             frame_identity: %{},
             caller_source: :sts,
             policy: Keyword.fetch!(options, :policy),
             usage_context: Keyword.get(options, :usage_context),
             output_stt_timeout_ms: Keyword.get(options, :output_stt_timeout_ms, 5_000)
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert is_pid(capability)
    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    {tree, capability, sink}
  end

  defp push_morse(capability, text) do
    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, text)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = SpeechToSpeech.push_audio(capability, @human, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = SpeechToSpeech.push_audio(capability, @human, tail)
    end
  end

  defp complete_playback(played_ms) do
    assert_receive {:test_audio_output_finish, sink, _turn}, 5_000
    TestAudioOutputSink.playback_progress(sink, played_ms, played_ms + 1_000)
    TestAudioOutputSink.playback_completed(sink)
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp deny_transcript(source, _recipient) do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: %{source => MapSet.new([])},
      record_audio: true,
      save_transcripts: true
    }
  end

  defp sts_usage_context do
    assert {:ok, provider} =
             Vxpipe.CallEngine.Usage.ProviderContext.new(
               name: "morse_code",
               integration_id: "local-sts",
               model: "morse-conversation"
             )

    [
      call_id: "call-sts-output-usage",
      participant_id: @agent,
      activation_id: "activation-sts",
      provider: provider,
      tenant_id: "tenant-sts-usage",
      room_id: "room-sts-usage",
      incarnation_id: "incarnation-sts-usage"
    ]
  end
end
