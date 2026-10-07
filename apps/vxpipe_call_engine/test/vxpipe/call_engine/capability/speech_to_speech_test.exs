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

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      identity: %{participant_id: @human},
                      event: %{kind: :input_transcript, text: "HI", final: true}
                    }}

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert_receive {:test_audio_output, _sink, frame}
    assert frame.sample_rate == 48_000

    source_samples =
      for <<sample::binary-size(2), _interpolated::binary-size(4) <- frame.payload>>,
        into: <<>>,
        do: sample

    assert source_samples == reply_pcm_prefix("RECEIVED HI", byte_size(source_samples))

    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _turn, 20,
                    _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}
    refute_received {:vxpipe_send_text, _, _, _}
  end

  test "caller input and interruption remain responsive while output is backpressured" do
    {_tree, capability, sink} = start_contract_capability()
    session = :sys.get_state(capability).session
    provider = Vxpipe.CallEngine.Speech.Session.provider(session)
    turn = make_ref()

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: turn, text: "CALLER", endpointing: :provider_gap]}
             )

    assert_receive {:sts_output_permitted, ^provider, _channel, ^turn, output_ref}
    assert :ok = GenServer.call(sink, {:block_output, true})
    assert {:ok, _credit} = GenServer.call(provider, {:output, output_ref})
    assert_receive {:test_audio_output, ^sink, frame}

    try do
      assert :ok = GenServer.call(capability, {:push_text, "Caller speaks"}, 100)
      assert_receive {:text_submission, _reference, [:ok]}
      assert {:ok, 0} = SpeechToSpeech.interrupt(capability)
      assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, 0, _, _}
      assert_receive {:vxpipe_speech_credit, _, ^output_ref, _, :ok}
      assert :ok = SpeechToSpeech.push_text(capability, "After the fence")
      refute_received {:vxpipe_sts_unavailable, ^capability, _}
    after
      # Release a blocked push even when the mailbox responsiveness assertion fails.
      GenServer.call(sink, {:vxpipe_audio_output_interrupt, frame.correlation_id, frame.reply_to})
    end
  end

  for rate <- [8_000, 16_000, 24_000, 48_000], report <- [40, 60] do
    test "#{rate} Hz source settlement excludes phone padding and validates #{report} ms playback" do
      {_tree, capability, sink} = start_contract_capability(sample_rate: unquote(rate))
      session = :sys.get_state(capability).session
      provider = Vxpipe.CallEngine.Speech.Session.provider(session)
      turn = make_ref()

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :turn_ended,
                  [turn_ref: turn, text: "CALLER", endpointing: :provider_gap]}
               )

      assert_receive {:sts_output_permitted, ^provider, _channel, ^turn, output_ref}
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn, _sequence}

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :output_transcript, [turn_ref: turn, text: "PARTIAL TAIL", final: true]}
               )

      pcm = :binary.copy(<<1, 0>>, div(unquote(rate), 50) + 1)
      assert {:ok, _credit} = GenServer.call(provider, {:output, output_ref, pcm})
      assert_receive {:test_audio_output, ^sink, frame}
      assert frame.sample_rate == 48_000
      assert byte_size(frame.payload) in 1_922..1_932
      assert_receive {:vxpipe_speech_credit, _, ^output_ref, _, :ok}

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :output_completed, [turn_ref: turn, request_ref: output_ref]}
               )

      assert_receive {:test_audio_output_finish, ^sink, _sink_turn}
      assert :ok = TestAudioOutputSink.playback_progress(sink, unquote(report), unquote(report))
      assert :ok = TestAudioOutputSink.playback_completed(sink)

      if unquote(report) == 40 do
        assert_receive {:vxpipe_speech_output_settled, _channel, ^turn, ^output_ref, 20}

        assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "PARTIAL TAIL", ^turn,
                        40, _, _}

        assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
        next = make_ref()

        assert :ok =
                 GenServer.call(
                   provider,
                   {:emit, :turn_ended,
                    [turn_ref: next, text: "NEXT", endpointing: :provider_gap]}
                 )

        assert_receive {:sts_output_permitted, ^provider, _, ^next, _}
      else
        assert_receive {:vxpipe_sts_unavailable, ^capability, :provider_failed}
        refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
      end
    end
  end

  test "queued legacy output keeps its acknowledged start order through playback" do
    {_tree, capability, sink} = start_contract_capability()
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    first = make_ref()
    second = make_ref()

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: first, text: "FIRST", endpointing: :provider_gap]}
             )

    assert_receive {:sts_output_permitted, ^provider, _, ^first, output_ref}
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^first, first_sequence}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended,
                [turn_ref: second, text: "SECOND", endpointing: :provider_gap]}
             )

    assert [{:legacy, ^second, second_sequence}] = :sys.get_state(capability).pending_turns
    assert second_sequence > first_sequence

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_transcript, [turn_ref: first, text: "FIRST", final: true]}
             )

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_completed, [turn_ref: first, request_ref: output_ref]}
             )

    assert_receive {:test_audio_output_finish, ^sink, _}
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^first, ^first_sequence}
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^second, ^second_sequence}
  end

  test "media-policy authority updates are enforced with revision tracking" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}

    denied = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 3,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: deny_audio(@human, @agent)
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, denied})
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _, _}

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
    refute_received {:vxpipe_sts_input_event, _, %{event: %{kind: :input_transcript}}}
    refute_received {:test_audio_output, _, _}
  end

  test "a settled transcript retains its admission interval across transcript revoke and regrant" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    snapshot = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: unrestricted()
    }

    assert :ok = GenServer.call(capability, {:vxpipe_apply_media_policy, snapshot})
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}

    assert :ok =
             GenServer.call(
               capability,
               {:vxpipe_apply_media_policy,
                %{snapshot | revision: 1, effective: deny_transcript(@agent, @human)}}
             )

    assert :ok =
             GenServer.call(capability, {:vxpipe_apply_media_policy, %{snapshot | revision: 2}})

    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn, 20,
                    0, _}
  end

  test "source mismatch fails closed" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert {:error, :source_mismatch} =
             SpeechToSpeech.push_audio(capability, " stranger ", <<0, 0>>)
  end

  test "mid-turn policy revocation fences queued output before the next interval" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert :ok = SpeechToSpeech.apply_policy(capability, deny_audio(@human, @agent))
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _, _}
    {:ok, pcm} = encode("HI")
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :policy_denied} = SpeechToSpeech.push_audio(capability, @human, first)
  end

  for api <- [:direct, :authority], phase <- [:generating, :draining] do
    test "#{api} outgoing-only revocation fences #{phase} output once" do
      {_tree, capability, sink} = start_contract_capability()
      provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
      turn = make_ref()

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :turn_ended, [turn_ref: turn, text: "HI", endpointing: :provider_gap]}
               )

      assert_receive {:sts_output_permitted, ^provider, _channel, ^turn, output}
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn, _}
      assert {:ok, _audio_ref} = GenServer.call(provider, {:output, output})
      assert_receive {:test_audio_output, ^sink, frame}
      assert_receive {:vxpipe_speech_credit, _, ^output, _, _}

      if unquote(phase) == :draining do
        assert :ok =
                 GenServer.call(
                   provider,
                   {:emit, :output_completed, [turn_ref: turn, request_ref: output]}
                 )

        assert_receive {:test_audio_output_finish, ^sink, _}
      end

      assert :ok = apply_directional_policy(capability, unquote(api), deny_egress())
      assert_receive {:test_audio_output_interrupt, ^sink, _, 0}
      assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, 0, :no_prefix, _}
      assert :sys.get_state(capability).active_output == nil
      assert :ok = SpeechToSpeech.push_audio(capability, @human, <<0, 0>>)

      if unquote(phase) == :generating do
        assert {:ok, _audio_ref} = GenServer.call(provider, {:output, output})
        assert_receive {:vxpipe_speech_credit, _, ^output, _, _}

        assert :ok =
                 GenServer.call(
                   provider,
                   {:emit, :output_completed, [turn_ref: turn, request_ref: output]}
                 )
      end

      assert_receive {:vxpipe_speech_output_settled, _, ^turn, ^output, 0}
      send(capability, {:vxpipe_audio_playback, sink, frame.correlation_id, {:completed, 100}})
      _ = :sys.get_state(capability)
      refute_received {:test_audio_output, ^sink, _}
      refute_received {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
      refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}

      assert :ok = apply_directional_policy(capability, unquote(api), unrestricted(), 1)
      next = make_ref()

      assert :ok =
               GenServer.call(
                 provider,
                 {:emit, :turn_ended, [turn_ref: next, text: "NEXT", endpointing: :provider_gap]}
               )

      assert_receive {:sts_output_permitted, ^provider, _, ^next, replacement}
      refute replacement == output
    end
  end

  test "output-only denial retires a new Morse reply without denying human input" do
    {_tree, capability, _sink} = start_capability(policy: deny_egress())
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)

    assert :ok = SpeechToSpeech.push_text(capability, "DENIED")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "DENIED"}}}

    state = :sys.get_state(capability)
    assert state.active_output == nil
    assert state.pending_turns == []
    assert :sys.get_state(provider).pending_replies == %{}
    assert :ok = SpeechToSpeech.push_audio(capability, @human, <<0, 0>>)

    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    assert :ok = SpeechToSpeech.push_text(capability, "FRESH")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, fresh, _}
    assert Map.has_key?(:sys.get_state(provider).pending_replies, fresh) == false
  end

  for api <- [:direct, :authority] do
    test "#{api} output-only revoke retires a queued Morse reply before regrant" do
      {_tree, capability, sink} = start_capability(policy: unrestricted())
      provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)

      assert :ok = SpeechToSpeech.push_text(capability, "FIRST")

      assert_receive {:vxpipe_sts_input_event, ^capability,
                      %{event: %{kind: :input_transcript, text: "FIRST"}}}

      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first, _}
      assert :ok = SpeechToSpeech.push_text(capability, "SECOND")

      assert_receive {:vxpipe_sts_input_event, ^capability,
                      %{event: %{kind: :input_transcript, text: "SECOND"}}}

      assert [{:legacy, second, _}] = :sys.get_state(capability).pending_turns
      assert second != first
      assert Map.has_key?(:sys.get_state(provider).pending_replies, second)

      assert :ok = apply_directional_policy(capability, unquote(api), deny_egress())
      assert_receive {:test_audio_output_interrupt, ^sink, _, 0}
      assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^first, 0, :no_prefix, _}
      assert :sys.get_state(capability).pending_turns == []
      refute Map.has_key?(:sys.get_state(provider).pending_replies, second)
      assert :ok = SpeechToSpeech.push_audio(capability, @human, <<0, 0>>)

      assert :ok = apply_directional_policy(capability, unquote(api), unrestricted(), 1)
      refute_received {:vxpipe_sts_turn_started, ^capability, @agent, ^second, _}
      refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^second, _, _, _}

      assert :ok = SpeechToSpeech.push_text(capability, "THIRD")
      assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, third, _}, 5_000
      assert third != first and third != second
      refute_received {:vxpipe_sts_turn_started, ^capability, @agent, ^second, _}
    end
  end

  test "a denied credited chunk is discarded without stranding its output slot" do
    alias Vxpipe.CallEngine.SpeechProviderContract, as: Contract
    alias Vxpipe.CallEngine.SpeechSTSContractProvider, as: Provider
    alias Vxpipe.CallEngine.Speech.Session
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output

    session = Contract.start_profile!(Provider, private: [observer: self()])
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    state = %{
      session: session,
      owner: self(),
      provider: Provider,
      sink: sink,
      agent_id: @agent,
      human_id: @human,
      output_stt: nil,
      active_output: nil,
      pending_turns: [],
      held?: false,
      policy: unrestricted(),
      input_policy: nil,
      policy_revision: 0,
      fenced_turns: MapSet.new(),
      usage_context: nil
    }

    turn = make_ref()
    assert {:noreply, state} = Output.admit_reply(turn, 1, state)
    provider = Session.provider(session)
    assert_receive {:sts_output_permitted, ^provider, _, ^turn, output}
    assert {:ok, credit} = GenServer.call(provider, {:output, output})
    audio = Contract.next_audio!(session, output, :binary.copy(<<0, 0>>, 320))
    assert {:noreply, state} = Output.handle_audio(audio, %{state | policy: deny_egress()})
    assert_receive {:vxpipe_speech_credit, _, ^output, ^credit, :ok}
    assert_receive {:vxpipe_sts_interrupted, _, @agent, ^turn, 0, :no_prefix, _}
    refute_received {:test_audio_output, ^sink, _}
    assert state.active_output == nil

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :output_completed, [turn_ref: turn, request_ref: output]}
             )

    completed = Contract.ack_event!(session, :output_completed)
    assert :ok = Output.settle_fenced_output(state, completed)
    assert {:ok, _replacement} = Session.admit_output(session, make_ref())
  end

  defp deny_egress,
    do: %{
      unrestricted()
      | audio_routes: %{@human => MapSet.new([@agent]), @agent => MapSet.new()}
    }

  defp apply_directional_policy(capability, api, policy, revision \\ 0)

  defp apply_directional_policy(capability, :direct, policy, _revision),
    do: SpeechToSpeech.apply_policy(capability, policy)

  defp apply_directional_policy(capability, :authority, policy, revision) do
    snapshot = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: policy
    }

    GenServer.call(capability, {:vxpipe_apply_media_policy, snapshot})
  end

  test "transcript-route denial suppresses transcripts without substituting audio" do
    {_tree, capability, _sink} =
      start_capability(policy: deny_transcript(@agent, @human))

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert_receive {:test_audio_output, _sink, _frame}
    complete_playback(20)
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, _turn, _}
  end

  test "with human STT selected, STS input text is suppressed and never dispatched as text-model input" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), caller_source: :human_stt)

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _, _,
                    _interval, _}

    refute_received {:vxpipe_sts_input_event, _, %{event: %{kind: :input_transcript}}}
    refute_received {:vxpipe_send_text, _, _, _}
  end

  test "hold fences output and blocks new input until released" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    assert :ok = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, _, _, _, _}
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
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    refute_received {:vxpipe_sts_turn_started, ^other_capability, _, _, _}

    monitor = Process.monitor(tree)
    capability_monitor = Process.monitor(capability)
    assert :ok = Supervisor.stop(tree, :normal, 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _reason}

    assert Process.alive?(other_capability)
    push_morse(other_capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^other_capability, @agent, _turn, _}
  end

  test "status redacts transcripts and stores no credentials" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}

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

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{
                      event: %{
                        kind: :tool_call,
                        call_ref: call_ref,
                        turn_ref: tool_turn,
                        tool_name: "echo",
                        arguments: %{"text" => "hi"}
                      }
                    }}

    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, reply_turn, _}
    assert tool_turn != reply_turn
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", _, _,
                    _interval, _}
  end

  test "interrupting a tool turn forwards cancellation and keeps old speech fenced" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{
                      event: %{
                        kind: :tool_call,
                        call_ref: call_ref,
                        turn_ref: turn_ref,
                        tool_name: "echo"
                      }
                    }}

    assert {:ok, _played} = SpeechToSpeech.interrupt(capability)

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_cancelled, call_ref: ^call_ref}}}

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn_ref, _, _, _}
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

  test "tool association overflow explicitly retires the capability and provider tree" do
    {tree, capability, _sink} = start_contract_capability()
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    capability_monitor = Process.monitor(capability)
    provider_monitor = Process.monitor(provider)
    tree_monitor = Process.monitor(tree)

    for _ <- 1..16 do
      assert :ok = emit_tool(provider, make_ref(), make_ref())
      assert_receive {:vxpipe_sts_tool_event, ^capability, @agent, %{event: %{kind: :tool_call}}}
    end

    assert map_size(:sys.get_state(capability).tool_calls) == 16
    assert :ok = emit_tool(provider, make_ref(), make_ref())
    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_tool_overflow}, 1_000

    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :pending_tool_overflow},
                   1_000

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _}, 1_000
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}, 1_000
  end

  test "tool evidence retains channel order and the original association on duplicates" do
    {_tree, capability, _sink} = start_contract_capability()
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    epoch = make_ref()
    assert :ok = SpeechToSpeech.release(capability, epoch)
    call = make_ref()
    turn = make_ref()
    assert :ok = emit_tool(provider, call, turn)

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{
                      epoch: ^epoch,
                      audio_interval: 0,
                      event: %{
                        kind: :tool_call,
                        call_ref: ^call,
                        turn_ref: ^turn,
                        sequence: sequence
                      }
                    }}

    assert is_integer(sequence) and sequence > 0
    original = :sys.get_state(capability).tool_calls
    assert :ok = emit_tool(provider, call, make_ref())
    marker = make_ref()
    assert :ok = emit_tool(provider, marker, make_ref())

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: ^marker}}}

    assert Map.fetch!(:sys.get_state(capability).tool_calls, call) == Map.fetch!(original, call)
    assert :ok = GenServer.call(provider, {:emit, :tool_cancelled, [call_ref: call]})

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{
                      epoch: ^epoch,
                      event: %{kind: :tool_cancelled, call_ref: ^call, sequence: terminal}
                    }}

    assert terminal > sequence
    assert map_size(original) == 1
    assert Map.keys(:sys.get_state(capability).tool_calls) == [marker]
    refute_received {:vxpipe_sts_tool_event, ^capability, _, _}
    refute_received {:vxpipe_sts_tool_call, _, _, _, _, _, _}
  end

  test "unknown results never reach a permissive provider" do
    {_tree, capability, _sink} = start_contract_capability()
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, make_ref(), %{})
    refute_received {:contract_tool_result, _, _}
  end

  test "revoked and regranted tool evidence cannot reach a permissive provider" do
    {_tree, capability, _sink} = start_contract_capability()
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    call = make_ref()
    assert :ok = emit_tool(provider, call, make_ref())
    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent, %{event: %{call_ref: ^call}}}
    assert :ok = SpeechToSpeech.apply_policy(capability, deny_audio(@human, @agent))
    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, call, %{})
    refute_received {:contract_tool_result, _, _}
  end

  test "hold retires tool associations and fences late results after release" do
    {_tree, capability, _sink} = start_contract_capability()
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    call = make_ref()
    assert :ok = emit_tool(provider, call, make_ref())
    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent, %{event: %{kind: :tool_call}}}
    assert :ok = SpeechToSpeech.hold(capability)
    assert :sys.get_state(capability).tool_calls == %{}
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, call, %{})
    refute_received {:contract_tool_result, _, _}
  end

  defp start_contract_capability(provider_options \\ []) do
    start_capability(
      policy: unrestricted(),
      provider: {Vxpipe.CallEngine.SpeechSTSContractProvider, provider_options},
      provider_private: [observer: self()]
    )
  end

  defp emit_tool(provider, call, turn) do
    GenServer.call(
      provider,
      {:emit, :tool_call, [call_ref: call, turn_ref: turn, tool_name: "echo", arguments: %{}]}
    )
  end

  test "provider speech onset fences active playback without a local interrupt" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first_turn, _}
    assert_receive {:test_audio_output, _sink, _frame}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      event: %{
                        kind: :input_transcript,
                        text: "HI",
                        turn_ref: ^first_turn,
                        final: true
                      }
                    }}

    {:ok, pcm} = encode("BY")

    for <<chunk::binary-size(320) <- binary_part(pcm, 0, min(byte_size(pcm), 960))>> do
      assert :ok = SpeechToSpeech.push_audio(capability, @human, chunk)
    end

    assert_receive {:vxpipe_sts_speech_started, ^capability, @agent, _onset_turn}

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^first_turn, _played, _prefix,
                    _}

    assert :sys.get_state(capability).active_output == nil

    refute_received {:vxpipe_sts_agent_transcript, ^capability, @agent, _, ^first_turn, _,
                     _interval, _}
  end

  test "unsolicited provider interruption fences active playback instead of reviving stale speech" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert_receive {:test_audio_output, _sink, _frame}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", turn_ref: ^turn, final: true}}}

    session = :sys.get_state(capability).session
    provider = Vxpipe.CallEngine.Speech.Session.provider(session)
    assert :ok = Vxpipe.Providers.MorseCode.STSSession.interrupt(provider, turn)

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _played, _prefix, _}
    assert :sys.get_state(capability).active_output == nil
    refute_received {:vxpipe_sts_agent_transcript, ^capability, @agent, _, ^turn, _, _interval, _}
    refute_received {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
  end

  test "caller transcripts distinguish partial updates from one settled final" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    transcripts = collect_transcripts(capability, turn, [])
    assert length(transcripts) >= 1
    assert Enum.count(transcripts, &match?({_, true}, &1)) == 1
    assert List.last(transcripts) |> elem(1) == true
  end

  test "settled STS turns emit usage observations with measured egress" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn, 20,
                    _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}
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
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert {:ok, _played} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}
    assert_receive {:vxpipe_usage_observations, ^capability, [observation]}
    assert observation.capability == :speech_to_speech
    assert observation.outcome == :cancelled
  end

  test "speech onset during output interrupts playback and the next turn proceeds" do
    {_tree, capability, sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, first_turn, _}
    assert_receive {:test_audio_output, _sink, _frame}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      event: %{
                        kind: :input_transcript,
                        text: "HI",
                        turn_ref: ^first_turn,
                        final: true
                      }
                    }}

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^first_turn, _played, _prefix,
                    _}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      event: %{
                        kind: :input_transcript,
                        text: "HI",
                        turn_ref: second_turn,
                        final: true
                      }
                    }}

    assert second_turn != first_turn
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^second_turn, _}
    complete_playback_for_turn(capability, sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI",
                    ^second_turn, 20, _interval, _}
  end

  test "zero-playback interruption publishes no spoken prefix" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    assert {:ok, 0} = SpeechToSpeech.interrupt(capability)
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, 0, :no_prefix, _}
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _interval, _}
    refute_received {:vxpipe_sts_turn_completed, _, _, _, _}
  end

  test "caller association overflow reports its cause and retires the owned tree" do
    {tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.CallEngine.SpeechSTSContractProvider, []},
        provider_private: [observer: self()]
      )

    session = :sys.get_state(capability).session
    provider = Vxpipe.CallEngine.Speech.Session.provider(session)
    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    provider_monitor = Process.monitor(provider)

    for _index <- 1..16 do
      turn = make_ref()
      assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: turn]})

      assert_receive {:vxpipe_sts_input_event, ^capability,
                      %{event: %{kind: :speech_started, turn_ref: ^turn}}}
    end

    assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: make_ref()]})
    assert_receive {:vxpipe_sts_unavailable, ^capability, :pending_caller_overflow}, 1_000

    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :pending_caller_overflow},
                   1_000

    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}, 1_000
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _}, 1_000
  end

  test "hold retires caller evidence and release uses the room-supplied epoch" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.CallEngine.SpeechSTSContractProvider, []},
        provider_private: [observer: self()]
      )

    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    first = make_ref()
    assert :ok = SpeechToSpeech.release(capability, first)
    assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: make_ref()]})
    assert_receive {:vxpipe_sts_input_event, ^capability, %{epoch: ^first}}
    assert :ok = SpeechToSpeech.hold(capability)
    assert :sys.get_state(capability).caller_turns == %{}
    second = make_ref()
    assert :ok = SpeechToSpeech.release(capability, second)
    assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: make_ref()]})
    assert_receive {:vxpipe_sts_input_event, ^capability, %{epoch: ^second}}
  end

  test "opening drops external caller activity without opening a provider input interval" do
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider} =
      bound_external_capability()

    assert :ok = SpeechToSpeech.begin_opening(capability, :generated)

    assert :ok =
             Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :started, epoch, %{
               input: 0,
               output: 0
             })

    _ = :sys.get_state(ingress)
    _ = :sys.get_state(capability)
    refute :sys.get_state(provider).external_started?
  end

  test "queued external activity reaches the capability through its bound ingress" do
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider} =
      bound_external_capability()

    assert :ok =
             Vxpipe.CallEngine.Media.STSIngress.activity(
               ingress,
               :started,
               epoch,
               %{input: 0, output: 0}
             )

    _ = :sys.get_state(capability)
    assert %{queued: 0, in_flight?: false} = Vxpipe.CallEngine.Media.STSIngress.stats(ingress)
    assert :sys.get_state(provider).external_started?
  end

  test "old-epoch activity cannot start a new external controller interval" do
    %{capability: capability, ingress: ingress, epoch: old_epoch, provider: provider} =
      bound_external_capability()

    assert :ok = SpeechToSpeech.hold(capability)
    new_epoch = make_ref()
    assert :ok = SpeechToSpeech.release(capability, new_epoch)
    old = make_ref()

    send(
      capability,
      {:vxpipe_sts_activity, ingress, old, :started, %{input: 0, output: 0}, old_epoch}
    )

    _ = :sys.get_state(capability)
    refute :sys.get_state(provider).external_started?

    assert :ok =
             Vxpipe.CallEngine.Media.STSIngress.activity(
               ingress,
               :started,
               new_epoch,
               %{input: 0, output: 0}
             )

    _ = :sys.get_state(capability)
    assert :sys.get_state(provider).external_started?
  end

  test "old audio interval cannot start external control after revoke and regrant" do
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider} =
      bound_external_capability()

    old_intervals = %{input: 0, output: 0}

    denied = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 1,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: deny_audio(@human, @agent)
    }

    granted = %{denied | revision: 2, effective: unrestricted()}

    for policy <- [denied, granted] do
      assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(capability, policy, 500)
      assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(ingress, policy, 500)
    end

    old = make_ref()
    send(capability, {:vxpipe_sts_activity, ingress, old, :started, old_intervals, epoch})
    _ = :sys.get_state(capability)
    refute :sys.get_state(provider).external_started?

    current = :sys.get_state(capability).input_policy

    intervals = %{
      input: Vxpipe.CallEngine.MediaPolicy.Snapshot.interval(current, :audio_input, @human),
      output: Vxpipe.CallEngine.MediaPolicy.Snapshot.interval(current, :audio_output, @human)
    }

    assert intervals.input != old_intervals.input
    assert_receive {:vxpipe_sts_activity_origin_changed, ^capability, 1}
    assert_receive {:vxpipe_sts_activity_origin_changed, ^capability, 2}

    assert {:error, :held} =
             Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :started, epoch, intervals)

    _ = :sys.get_state(capability)
    refute :sys.get_state(provider).external_started?
  end

  test "unrelated policy revision preserves external input origin" do
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider} =
      bound_external_capability()

    unchanged = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 1,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: unrestricted()
    }

    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(capability, unchanged, 500)
    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(ingress, unchanged, 500)
    refute_received {:vxpipe_sts_activity_origin_changed, ^capability, _revision}

    assert :ok =
             Vxpipe.CallEngine.Media.STSIngress.activity(
               ingress,
               :started,
               epoch,
               %{input: 0, output: 0}
             )

    _ = :sys.get_state(capability)
    assert :sys.get_state(provider).external_started?
  end

  test "direct external activity start cannot survive capability hold" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    assert {:error, :unavailable} = SpeechToSpeech.input_activity(capability, :ended)
  end

  test "dirty external activity fails the STS allocation closed on hold" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    push_morse(capability, "HI")
    assert :sys.get_state(provider).decoder_final == "HI"
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    assert {:error, :unavailable} = SpeechToSpeech.release(capability, make_ref())
    refute_receive {:test_audio_output_finish, ^sink, _turn}, 500
  end

  test "hybrid PCM without an external start also fails closed on hold" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "hybrid"]}
      )

    push_morse(capability, "HI")
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    refute_receive {:test_audio_output_finish, ^sink, _turn}, 500
  end

  test "text tool completion cannot make buffered hybrid PCM safe to hold" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "hybrid"]}
      )

    {:ok, pcm} = encode("E")
    assert :ok = SpeechToSpeech.push_audio(capability, @human, binary_part(pcm, 0, 1_920))
    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    assert {:error, :unavailable} = SpeechToSpeech.release(capability, make_ref())
    refute_receive {:test_audio_output_finish, ^sink, _turn}, 500
  end

  test "settled external Morse output permits an idle hold and release" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    push_morse(capability, "HI")
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    sink_turn = :sys.get_state(capability).active_output.sink_turn
    assert_receive {:test_audio_output_finish, ^sink, ^sink_turn}, 5_000
    %{output: %{turn_ref: native_turn, output_ref: output_ref}} = :sys.get_state(provider)

    send(provider, {:vxpipe_speech_output_settled, self(), native_turn, make_ref(), 0})
    assert %{output: %{output_ref: ^output_ref}} = :sys.get_state(provider)

    TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}

    assert %{
             input_dirty?: false,
             external_started?: false,
             input_turn: nil,
             decoder_final: nil,
             pending_replies: %{},
             pending_tools: %{},
             output: nil
           } = :sys.get_state(provider)

    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())
  end

  test "direct external activity is denied when caller output is revoked" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    assert :ok = SpeechToSpeech.apply_policy(capability, deny_egress())
    assert {:error, :policy_denied} = SpeechToSpeech.input_activity(capability, :ended)
  end

  test "direct activity cannot bypass a bound ingress" do
    %{capability: capability, ingress: ingress} = bound_external_capability()
    assert :ok = :sys.suspend(ingress)

    try do
      assert {:error, :input_owned_by_ingress} =
               SpeechToSpeech.input_activity(capability, :started)
    after
      :sys.resume(ingress)
    end
  end

  test "a nil ingress activity envelope cannot crash an unbound capability" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    send(
      capability,
      {:vxpipe_sts_activity, nil, make_ref(), :started, %{input: 0, output: 0}, make_ref()}
    )

    assert %{input: nil} = :sys.get_state(capability)
  end

  test "hold racing delivered activity retires the control without killing the capability" do
    %{capability: capability, ingress: ingress, epoch: epoch} = bound_external_capability()
    assert :ok = :sys.suspend(capability)
    call = make_ref()

    try do
      send(capability, {:"$gen_call", {self(), call}, :hold})

      assert :ok =
               Vxpipe.CallEngine.Media.STSIngress.activity(
                 ingress,
                 :started,
                 epoch,
                 %{input: 0, output: 0}
               )
    after
      :sys.resume(capability)
    end

    assert_receive {^call, :ok}
    _ = :sys.get_state(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())
  end

  test "queued external end cannot reopen old input after hold" do
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider} =
      bound_external_capability()

    intervals = %{input: 0, output: 0}
    assert :ok = Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :started, epoch, intervals)
    _ = :sys.get_state(capability)
    assert :sys.get_state(provider).external_started?

    assert :ok = :sys.suspend(capability)
    monitor = Process.monitor(capability)

    try do
      send(capability, {:"$gen_call", {self(), make_ref()}, :hold})
      assert :ok = Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :ended, epoch, intervals)
    after
      :sys.resume(capability)
    end

    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    assert {:error, :unavailable} = SpeechToSpeech.release(capability, make_ref())
  end

  test "capability-first output revocation retires a queued activity without killing input" do
    %{capability: capability, ingress: ingress, epoch: epoch} = bound_external_capability()

    denied = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 1,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: deny_egress()
    }

    assert :ok = :sys.suspend(capability)
    policy_call = make_ref()

    try do
      intervals = %{input: 0, output: 0}

      assert :ok =
               Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :started, epoch, intervals)

      assert :ok = Vxpipe.CallEngine.Media.STSIngress.activity(ingress, :ended, epoch, intervals)

      send(
        capability,
        {:"$gen_call", {self(), policy_call}, {:vxpipe_apply_media_policy, denied}}
      )
    after
      :sys.resume(capability)
    end

    assert_receive {^policy_call, :ok}
    _ = :sys.get_state(ingress)
    _ = :sys.get_state(capability)

    assert %{queued: 0, in_flight?: false} =
             Vxpipe.CallEngine.Media.STSIngress.stats(ingress)

    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(ingress, denied, 500)
    _ = :sys.get_state(capability)
  end

  defp bound_external_capability do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {Vxpipe.Providers.MorseCode.STSSession, [turn_control: "external"]}
      )

    identity = %{
      tenant_id: "sts-tenant",
      room_id: "sts-room",
      incarnation_id: "sts-incarnation",
      participant_id: @human,
      connection_id: "source"
    }

    assert {:ok, format} = SpeechToSpeech.input_format(capability)

    assert {:ok, ingress} =
             SpeechToSpeech.Tree.start_input(capability,
               source_connection: self(),
               identity: identity,
               agent_id: @agent,
               format: format,
               delivery_timeout_ms: 100
             )

    assert :ok = SpeechToSpeech.bind_input(capability, ingress)

    snapshot = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: unrestricted()
    }

    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(capability, snapshot, 500)
    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(ingress, snapshot, 500)

    assert :ok =
             Vxpipe.CallEngine.Media.STSIngress.prepare_track(
               ingress,
               Map.put(format, :track_id, "microphone")
             )

    epoch = make_ref()
    assert :ok = SpeechToSpeech.release(capability, epoch)
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    %{capability: capability, ingress: ingress, epoch: epoch, provider: provider}
  end

  defp start_capability(options) do
    alias Vxpipe.CallEngine.Speech.PrivateInit

    startup_timeout_ms = 5_000
    owner = Keyword.get(options, :owner, self())
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {:ok, private_init} =
      PrivateInit.open(Keyword.get(options, :provider_private, []), startup_timeout_ms)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: owner,
             agent_id: @agent,
             human_id: @human,
             provider:
               Keyword.get(options, :provider, {Vxpipe.Providers.MorseCode.STSSession, []}),
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
      assert_receive {:vxpipe_sts_ready, ^capability}, startup_timeout_ms
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
      {:vxpipe_sts_input_event, ^capability,
       %{event: %{kind: :input_transcript, text: text, turn_ref: ^turn, final: final?}}} ->
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
