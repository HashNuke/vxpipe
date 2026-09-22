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

  test "recognition readiness preserves every pending reply in order" do
    {_tree, capability, _sink} = start_deferred_output_stt()
    assert_receive {:output_stt_waiting, recognizer}

    turns =
      for text <- ["ONE", "TWO", "THREE"] do
        assert :ok = SpeechToSpeech.push_text(capability, text)
        assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, ^text, turn, true}
        turn
      end

    assert :ok = Vxpipe.CallEngine.SpeechOutputSTTSlowProvider.release_ready(recognizer)

    for turn <- turns do
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn}, 1_000
      complete_playback(20)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}, 1_000
    end
  end

  test "pending reply overflow fails the allocation instead of growing without bound" do
    {tree, capability, _sink} = start_deferred_output_stt()
    monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    assert_receive {:output_stt_waiting, _recognizer}

    for _ <- 1..17 do
      assert :ok = SpeechToSpeech.push_text(capability, "HI")
      assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", _turn, true}
    end

    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_turn_overflow}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :pending_turn_overflow}, 1_000
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 1_000
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _}
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

    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", _turn, _final}
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _turn, 20}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
    refute_received {:vxpipe_sts_input_transcript, ^capability, @agent, _, _, _}
  end

  test "denied transcript policy settles the turn without agent text" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: deny_transcript(@agent, @human))

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}
  end

  test "output STT failure at finalization settles honestly without agent text" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTFailingProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}
  end

  test "output STT loss still settles and the next turn recovers" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: unrestricted(), output_stt_timeout_ms: 300)

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}

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
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}, 5_000

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn2}, 5_000
    assert turn2 != turn
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn2, 20},
                   5_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn2}
    refute_received {:DOWN, ^capability_monitor, :process, ^capability, _}
  end

  test "settled output-STT turns attribute both the STS and recognition legs" do
    {_tree, capability, _sink} =
      start_output_stt_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}
    assert_receive {:vxpipe_usage_observations, ^capability, observations}

    assert Enum.map(observations, & &1.capability) |> Enum.sort() == [
             :output_speech_to_text,
             :speech_to_speech
           ]

    assert Enum.all?(observations, &(&1.outcome == :succeeded))
    assert Enum.all?(observations, &(&1.attribution.participant_id == @agent))
  end

  test "output STT finalization errors are explicit instead of silent" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTFailingProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}, 5_000
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
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}, 2_000
    assert_receive {:vxpipe_sts_output_stt_unavailable, ^capability, :timeout}, 2_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
  end

  test "output-STT audio arriving before recognition readiness is buffered, not dropped" do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output, as: STS

    {_tree, capability, _sink} = start_output_stt_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}

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

  test "a slow output STT consumer cannot block sink audio" do
    {_tree, capability, _sink} =
      start_output_stt_capability(
        policy: unrestricted(),
        output_stt: {Vxpipe.CallEngine.SpeechOutputSTTSlowProvider, []}
      )

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "SLOW RESULT", _, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}

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
             provider: {Vxpipe.Providers.MorseCode.STSSession, [output_transcript: false]},
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
