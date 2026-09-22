defmodule Vxpipe.CallEngine.Capability.SpeechToSpeechTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.TestAudioOutputSink

  @human "human1"
  @agent "agent1"

  test "one human audio turn produces morse reply audio and agent-attributed transcript" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", _turn, true}
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert_receive {:test_audio_output, _sink, frame}
    assert frame.payload == reply_pcm_prefix("RECEIVED HI", byte_size(frame.payload))

    complete_playback(20)
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _turn, 20}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}
    refute_received {:vxpipe_send_text, _, _, _}
  end

  test "media-policy authority updates are enforced with revision tracking" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}

    denied = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 3,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: deny_audio(@human, @agent)
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, denied})
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _}

    {:ok, pcm} = encode("HI")
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, @human, first)

    state = :sys.get_state(capability)
    assert state.policy_revision == 3
  end

  test "policy denial fails closed without provider input" do
    {_tree, capability, _sink} =
      start_capability(policy: deny_audio(@human, @agent))

    {:ok, pcm} = encode("HI")
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, @human, first)
    refute_received {:vxpipe_sts_input_transcript, _, _, _, _, _}
    refute_received {:test_audio_output, _, _}
  end

  test "source mismatch fails closed" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert {:error, :source_mismatch} =
             SpeechToSpeech.push_audio(capability, " stranger ", <<0, 0>>)
  end

  test "mid-turn policy revocation fences queued output before the next interval" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert :ok = SpeechToSpeech.apply_policy(capability, deny_audio(@human, @agent))
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _}
    {:ok, pcm} = encode("HI")
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, @human, first)
  end

  test "transcript-route denial suppresses transcripts without substituting audio" do
    {_tree, capability, _sink} =
      start_capability(policy: deny_transcript(@agent, @human))

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn}
  end

  test "with human STT selected, STS input text is suppressed and never dispatched as text-model input" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), caller_source: :human_stt)

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    complete_playback(20)
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _, _}
    refute_received {:vxpipe_sts_input_transcript, _, _, _, _, _}
    refute_received {:vxpipe_send_text, _, _, _}
  end

  test "hold fences output and blocks new input until released" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    assert :ok = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _}
    {:ok, pcm} = encode("HI")
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :held} = SpeechToSpeech.push_audio(capability, @human, first)
    assert :ok = SpeechToSpeech.release(capability)
    assert :ok = SpeechToSpeech.push_audio(capability, @human, first)
  end

  test "teardown closes the owned tree without cross-room state" do
    {tree, capability, _sink} = start_capability(policy: unrestricted())
    {_other_tree, other_capability, _other_sink} = start_capability(policy: unrestricted())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}
    refute_received {:vxpipe_sts_turn_started, ^other_capability, _, _}

    monitor = Process.monitor(tree)
    capability_monitor = Process.monitor(capability)
    assert :ok = Supervisor.stop(tree, :normal, 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _reason}

    assert Process.alive?(other_capability)
    push_morse(other_capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^other_capability, @agent, _turn}
  end

  test "status redacts transcripts and stores no credentials" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn}

    redacted =
      SpeechToSpeech.format_status(%{
        state: :secret,
        message: "RECEIVED HI",
        reason: "HI",
        log: ["HI"]
      })

    refute inspect(redacted) =~ "RECEIVED HI"
    refute inspect(:sys.get_state(capability)) =~ "api_key"
  end

  test "tool calls are forwarded with agent attribution and results return without reviving speech" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_call, ^capability, @agent, call_ref, tool_turn, "echo",
                    %{"text" => "hi"}}

    refute_received {:vxpipe_sts_turn_started, ^capability, _, _}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, reply_turn}
    assert tool_turn != reply_turn
    complete_playback(20)
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _, _}
  end

  test "interrupting a tool turn forwards cancellation and keeps old speech fenced" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")
    assert_receive {:vxpipe_sts_tool_call, ^capability, @agent, call_ref, turn_ref, "echo", _args}

    assert {:ok, _played} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_sts_tool_cancelled, ^capability, @agent, ^call_ref}
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn_ref, _, _}
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, call_ref, %{})
  end

  test "owner loss ends the owned capability tree" do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {tree, capability, _sink} = start_capability(owner: owner, policy: unrestricted())

    tree_monitor = Process.monitor(tree)
    capability_monitor = Process.monitor(capability)
    owner_monitor = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, _reason}
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _reason}
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}
  end

  test "provider speech onset fences active playback without a local interrupt" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first_turn}
    assert_receive {:test_audio_output, _sink, _frame}
    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", ^first_turn, true}

    {:ok, pcm} = encode("BY")

    for <<chunk::binary-size(320) <- binary_part(pcm, 0, min(byte_size(pcm), 960))>> do
      assert :ok = SpeechToSpeech.push_audio(capability, @human, chunk)
    end

    assert_receive {:vxpipe_sts_speech_started, ^capability, @agent, _onset_turn}
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^first_turn, _played, _prefix}
    assert :sys.get_state(capability).active_output == nil
    refute_received {:vxpipe_sts_agent_transcript, ^capability, @agent, _, ^first_turn, _}
  end

  test "unsolicited provider interruption fences active playback instead of reviving stale speech" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    assert_receive {:test_audio_output, _sink, _frame}
    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", ^turn, true}

    session = :sys.get_state(capability).session
    provider = Vxpipe.CallEngine.Speech.Session.provider(session)
    assert :ok = Vxpipe.Providers.MorseCode.STSSession.interrupt(provider, turn)

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _played, _prefix}
    assert :sys.get_state(capability).active_output == nil
    refute_received {:vxpipe_sts_agent_transcript, ^capability, @agent, _, ^turn, _}
    refute_received {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}
  end

  test "caller transcripts distinguish partial updates from one settled final" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    transcripts = collect_transcripts(capability, turn, [])
    assert length(transcripts) >= 1
    assert Enum.count(transcripts, &match?({_, true}, &1)) == 1
    assert List.last(transcripts) |> elem(1) == true
  end

  test "settled STS turns emit usage observations with measured egress" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    complete_playback(20)
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn, 20}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}
    assert_receive {:vxpipe_usage_observations, ^capability, [observation]}
    assert observation.capability == :speech_to_speech
    assert observation.outcome == :succeeded
    assert observation.attribution.participant_id == @agent
    assert observation.measurement.unit == :milliseconds
    assert observation.measurement.quantity == 20
    assert observation.provider.name == "morse_code"
  end

  test "interrupted STS turns emit cancelled usage observations" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    assert {:ok, _played} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _}
    assert_receive {:vxpipe_usage_observations, ^capability, [observation]}
    assert observation.capability == :speech_to_speech
    assert observation.outcome == :cancelled
  end

  test "speech onset during output interrupts playback and the next turn proceeds" do
    {_tree, capability, sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first_turn}
    assert_receive {:test_audio_output, _sink, _frame}
    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", ^first_turn, true}

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^first_turn, _played, _prefix}

    assert_receive {:vxpipe_sts_input_transcript, ^capability, @human, "HI", second_turn, true}
    assert second_turn != first_turn
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^second_turn}
    complete_playback_for_turn(capability, sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI",
                    ^second_turn, 20}
  end

  test "zero-playback interruption publishes no spoken prefix" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn}
    assert {:ok, 0} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, 0, :no_prefix}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _}
  end

  defp start_capability(options) do
    alias Vxpipe.CallEngine.Speech.PrivateInit

    owner = Keyword.get(options, :owner, self())
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
    {:ok, private_init} = PrivateInit.open([], 5_000)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: owner,
             agent_id: @agent,
             human_id: @human,
             provider: {Vxpipe.Providers.MorseCode.STSSession, []},
             provider_private: private_init,
             sink: sink,
             frame_identity: %{},
             caller_source: Keyword.get(options, :caller_source, :sts),
             policy: Keyword.fetch!(options, :policy),
             usage_context: Keyword.get(options, :usage_context)
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert is_pid(capability)

    if owner == self() do
      assert_receive {:vxpipe_sts_ready, ^capability}
    end

    {tree, capability, sink}
  end

  defp push_morse(capability, text) do
    {:ok, pcm} = encode(text)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = SpeechToSpeech.push_audio(capability, @human, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = SpeechToSpeech.push_audio(capability, @human, tail)
    end
  end

  defp encode(text) do
    {:ok, config} = Config.new([])
    Encoder.encode(config, text)
  end

  defp input_pcm(_text) do
    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, "RECEIVED HI")
    pcm
  end

  defp reply_pcm_prefix(_text, size) do
    binary_part(input_pcm(""), 0, size)
  end

  defp complete_playback_for_turn(capability, sink) do
    sink_turn = :sys.get_state(capability) |> Map.fetch!(:active_output) |> Map.fetch!(:sink_turn)
    assert_receive {:test_audio_output_finish, ^sink, ^sink_turn}, 5_000
    TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    TestAudioOutputSink.playback_completed(sink)
  end

  defp complete_playback(played_ms) do
    assert_receive {:test_audio_output_finish, sink, _turn}, 5_000
    TestAudioOutputSink.playback_progress(sink, played_ms, played_ms + 1_000)
    TestAudioOutputSink.playback_completed(sink)
  end

  defp collect_transcripts(capability, turn, acc) do
    receive do
      {:vxpipe_sts_input_transcript, ^capability, @human, text, ^turn, final?} ->
        collect_transcripts(capability, turn, [{text, final?} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
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
      call_id: "call-sts-usage",
      participant_id: @agent,
      activation_id: "activation-sts",
      provider: provider,
      tenant_id: "tenant-sts-usage",
      room_id: "room-sts-usage",
      incarnation_id: "incarnation-sts-usage"
    ]
  end

  defp deny_audio(source, _recipient) do
    %Effective{
      audio_routes: %{source => MapSet.new([])},
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
end
