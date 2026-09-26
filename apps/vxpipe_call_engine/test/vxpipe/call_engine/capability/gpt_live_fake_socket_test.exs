defmodule Vxpipe.CallEngine.Capability.GPTLiveFakeSocketTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TestGPTLiveTransport
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  @delegation_fixture Path.expand(
                        "../../../support/fixtures/gpt_live/delegated_tools.jsonl",
                        __DIR__
                      )

  @capability_fixture Path.expand(
                        "../../../support/fixtures/gpt_live/capability_events.jsonl",
                        __DIR__
                      )

  test "only completed delegated calls reach the capability and all results precede continuation" do
    {capability, wire} = start_ready_capability()
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    deliver_fixture(wire, "delegation")
    deliver_fixture(wire, "pending")
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(provider)
    refute_receive {:vxpipe_sts_tool_event, ^capability, _, _}, 50

    deliver_fixture(wire, "first")
    deliver_fixture(wire, "first")
    deliver_fixture(wire, "second")
    deliver_fixture(wire, "completed")

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent1",
                    %{event: %{kind: :tool_call, call_ref: first, arguments: %{"value" => "a"}}}}

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent1",
                    %{event: %{kind: :tool_call, call_ref: second, arguments: %{"value" => "b"}}}}

    assert first != second
    _ = :sys.get_state(provider)
    refute_receive {:vxpipe_sts_tool_event, ^capability, _, _}, 50

    assert :ok = SpeechToSpeech.send_tool_result(capability, first, %{"ok" => "a"})
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.item.create"}}
    refute_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}, 50

    assert :ok = SpeechToSpeech.send_tool_result(capability, second, %{"ok" => "b"})
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.item.create"}}
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, first, %{})
  end

  test "failed and incomplete delegations retire their capability tool calls" do
    for terminal <- ["failed", "incomplete"] do
      {capability, wire} = start_ready_capability()
      assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
      assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

      deliver_fixture(wire, "delegation")
      deliver_fixture(wire, "first")

      assert_receive {:vxpipe_sts_tool_event, ^capability, "agent1",
                      %{event: %{kind: :tool_call, call_ref: call_ref}}}

      deliver_fixture(wire, terminal)
      provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
      _ = :sys.get_state(provider)

      assert {:error, :stale_request} =
               SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

      deliver_fixture(wire, "first")
      _ = :sys.get_state(provider)
      refute_receive {:vxpipe_sts_tool_event, ^capability, _, _}, 50
      refute_receive {:test_gpt_live_control, ^wire, %{"type" => "response.item.create"}}, 50
      refute_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}, 50
    end
  end

  test "a tool result from the lost session reaches the replacement as private context" do
    {capability, wire} = start_ready_capability()
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    deliver_fixture(wire, "delegation")
    deliver_fixture(wire, "first")
    deliver_fixture(wire, "completed")

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent1",
                    %{event: %{kind: :tool_call, call_ref: call_ref}}}

    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}, 1_000

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"answer" => 42})

    refute_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.thinking.append"}},
                   50

    TestGPTLiveTransport.deliver_sync(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.thinking.append", "content" => note}},
                   1_000

    assert String.contains?(note, "echo")
    assert String.contains?(note, ~s("answer":42))
    refute_received {:test_gpt_live_control, ^replacement, %{"type" => "response.item.create"}}
    assert {:error, :stale_request} = SpeechToSpeech.send_tool_result(capability, call_ref, %{})
  end

  test "a late delegated call keeps its retired response context and receives a denial" do
    {capability, wire} = start_ready_capability()
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    deliver_fixture(wire, "delegation")
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(provider)

    assert :ok = SpeechToSpeech.apply_policy(capability, unrestricted())
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    deliver_fixture(wire, "first")
    deliver_fixture(wire, "completed")

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "response.item.create", "item" => denied}},
                   1_000

    assert denied["call_id"] == "a"
    assert String.contains?(denied["output"], "no_longer_permitted")
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}, 1_000
    refute_received {:vxpipe_sts_tool_event, ^capability, _, _}
  end

  test "two GPT-Live audio bursts from one answer settle as separate capability turns" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    tone = :binary.copy(<<0, 16>>, 480)
    silence = :binary.copy(<<0, 0>>, 480 * 2)

    for {text, start_ms, end_ms} <- [{"Hello", 100, 120}, {"again", 160, 180}] do
      TestGPTLiveTransport.deliver(wire, %{
        "type" => "session.output_transcript.delta",
        "delta" => text,
        "start_ms" => start_ms,
        "end_ms" => end_ms
      })

      TestGPTLiveTransport.deliver(wire, %{
        "type" => "session.output_audio.delta",
        "delta" => Base.encode64(tone <> silence)
      })

      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent1", turn, _}, 1_000
      assert_receive {:test_audio_output, sink, _frame}, 1_000
      assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
      TestAudioOutputSink.playback_progress(sink, 60, 60)
      TestAudioOutputSink.playback_completed(sink)

      assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent1", ^text, ^turn, _, _, _},
                     1_000
    end
  end

  test "caller speech overlaps a fake GPT-Live reply until the provider yields" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    deliver_capability_fixture(wire, "agent_hello")
    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent1", turn, _}, 1_000
    assert_receive {:test_audio_output, sink, _frame}, 1_000

    deliver_capability_fixture(wire, "caller_yes")
    assert_receive {:vxpipe_sts_speech_started, ^capability, "agent1", _caller_turn}, 1_000
    refute_received {:vxpipe_sts_interrupted, ^capability, "agent1", ^turn, _, _, _}

    silence = :binary.copy(<<0, 0>>, 480 * 2)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(silence)
    })

    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    TestAudioOutputSink.playback_progress(sink, 60, 60)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent1", "Hello", ^turn, _, _, _},
                   1_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent1", ^turn, _}, 1_000
    refute_received {:vxpipe_sts_interrupted, ^capability, "agent1", ^turn, _, _, _}
  end

  test "a policy-denied GPT-Live burst is discarded before playback" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    assert :ok = SpeechToSpeech.apply_policy(capability, deny_agent_audio())

    deliver_capability_fixture(wire, "agent_hello")
    tone = :binary.copy(<<0, 16>>, 480)
    silence = :binary.copy(<<0, 0>>, 480 * 2)

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone <> silence)
    })

    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(provider)
    _ = :sys.get_state(capability)
    refute_received {:vxpipe_sts_turn_started, ^capability, "agent1", _, _}
    refute_received {:test_audio_output, _, _}
    refute_received {:vxpipe_sts_agent_transcript, ^capability, "agent1", _, _, _, _, _}
    assert :sys.get_state(capability).active_output == nil
  end

  test "a second lost socket fails the speech capability with reseed_failed" do
    {capability, wire} = start_ready_capability()
    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}
    TestGPTLiveTransport.disconnect(replacement)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :reseed_failed}, 1_000
    refute_receive {:test_gpt_live_started, _, _}, 50
  end

  test "an idle replacement waits for caller input before speaking" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    TestGPTLiveTransport.disconnect(wire)

    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}, 1_000

    TestGPTLiveTransport.deliver_sync(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(provider)

    refute_received {:test_gpt_live_control, ^replacement,
                     %{"type" => "session.commentary.append"}}

    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.input_audio.append"}},
                   1_000

    assert_replacement_speaks(capability, replacement)
  end

  test "an unanswered caller turn resumes as audible speech after reseed" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    deliver_capability_fixture(wire, "caller_hi")

    silence = :binary.copy(<<0, 0>>, div(24_000 * 800, 1_000))
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", silence)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "Hi", final: true}}},
                   1_000

    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}, 1_000

    TestGPTLiveTransport.deliver_sync(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.commentary.append"}},
                   1_000

    assert_replacement_speaks(capability, replacement)
  end

  test "a drop during an agent burst settles heard audio then replacement speech" do
    {capability, wire} = start_ready_capability(output_gap_ms: 40)
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    deliver_capability_fixture(wire, "agent_hello")

    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    TestGPTLiveTransport.disconnect(wire)

    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent1", first_turn, _}, 1_000
    assert_receive {:test_audio_output, sink, _frame}, 1_000
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}, 1_000

    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    TestAudioOutputSink.playback_progress(sink, 20, 20)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent1", "Hello", ^first_turn, _,
                    _, _},
                   1_000

    TestGPTLiveTransport.deliver_sync(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.commentary.append"}},
                   1_000

    assert_replacement_speaks(capability, replacement)
  end

  test "a replacement that misses readiness fails the speech capability within its deadline" do
    {capability, wire} = start_ready_capability()
    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}
    assert_receive {:vxpipe_sts_unavailable, ^capability, :reseed_failed}, 6_000
  end

  test "a content close reports moderation to the speech capability owner" do
    {capability, wire} = start_ready_capability()
    deliver_capability_fixture(wire, "content")
    assert_receive {:vxpipe_sts_unavailable, ^capability, :moderation}, 1_000
  end

  test "ordinary close reasons stop the provider without a replacement socket" do
    for name <- ["closed_requested", "remote_hangup"] do
      {capability, wire} = start_ready_capability()
      provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
      monitor = Process.monitor(provider)
      deliver_capability_fixture(wire, name)
      assert_receive {:DOWN, ^monitor, :process, ^provider, :normal}, 1_000
      assert_receive {:vxpipe_sts_unavailable, ^capability, :provider_failed}, 1_000
      refute_receive {:test_gpt_live_started, _, _}, 50
    end
  end

  test "malformed and unknown socket events fail the real speech capability" do
    for name <- ["malformed", "unknown"] do
      {capability, wire} = start_ready_capability()
      provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
      monitor = Process.monitor(provider)
      deliver_capability_fixture(wire, name)

      assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :invalid_message}},
                     1_000

      assert_receive {:vxpipe_sts_unavailable, ^capability, :provider_failed}, 1_000
    end
  end

  test "a fake GPT-Live caller fragment and spoken burst pass through the real capability" do
    {:ok, config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {:ok, private} =
      PrivateInit.open(
        [
          config: config,
          wire_module: TestGPTLiveTransport,
          wire_options: [observer: self()],
          output_gap_ms: 40
        ],
        5_000
      )

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: self(),
             agent_id: "agent1",
             human_id: "human1",
             provider: {GPTLiveSession, [backend_model: "gpt-5.6"]},
             provider_private: private,
             sink: sink,
             frame_identity: %{},
             caller_source: :sts,
             policy: unrestricted()
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:test_gpt_live_started, wire, _connection}, 5_000

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.start", "session" => %{"store" => false}}}

    refute_received {:vxpipe_sts_ready, ^capability}

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000

    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    deliver_capability_fixture(wire, "caller_hi")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "Hi"}}},
                   1_000

    input_silence = :binary.copy(<<0, 0>>, div(24_000 * 800, 1_000))
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", input_silence)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "Hi", final: true}}},
                   1_000

    deliver_capability_fixture(wire, "agent_hello")

    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    assert :sys.get_state(provider).bursts.last_index == 1
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent1", turn, _}, 1_000
    assert_receive {:test_audio_output, ^sink, _frame}, 1_000
    assert_receive {:test_audio_output_finish, ^sink, _}, 2_000
    TestAudioOutputSink.playback_progress(sink, 60, 60)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent1", "Hello", ^turn, _, _, _},
                   1_000

    deliver_capability_fixture(wire, "expired")
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.start", "session" => reseed}},
                   1_000

    assert reseed["input"] == [
             %{
               "type" => "message",
               "role" => "user",
               "content" => [%{"type" => "input_text", "text" => "Hi"}]
             },
             %{
               "type" => "message",
               "role" => "assistant",
               "content" => [%{"type" => "input_text", "text" => "Hello"}]
             }
           ]
  end

  test "provider voice and delegated backend usage become distinct call observations" do
    {:ok, config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {:ok, private} =
      PrivateInit.open(
        [config: config, wire_module: TestGPTLiveTransport, wire_options: [observer: self()]],
        5_000
      )

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: self(),
             agent_id: "agent1",
             human_id: "human1",
             provider: {GPTLiveSession, [backend_model: "gpt-5.6"]},
             provider_private: private,
             sink: sink,
             frame_identity: %{},
             caller_source: :sts,
             policy: unrestricted(),
             usage_context: %{
               tenant_id: "tenant1",
               call_id: "call1",
               room_id: "room1",
               incarnation_id: "inc1",
               participant_id: "agent1"
             }
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:test_gpt_live_started, wire, _connection}, 5_000
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}, 5_000

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000

    deliver_capability_fixture(wire, "voice_125")

    assert_receive {:vxpipe_usage_observations, ^capability, [voice]}
    assert voice.capability == :speech_to_speech
    assert voice.provider.model == "gpt-live-1"
    assert voice.measurement.quantity == 1_250
    assert voice.measurement.provenance == :provider_reported

    deliver_capability_fixture(wire, "voice_125")
    deliver_capability_fixture(wire, "voice_150")

    assert_receive {:vxpipe_usage_observations, ^capability, [voice_delta]}
    assert voice_delta.measurement.quantity == 250

    deliver_capability_fixture(wire, "backend_delegation")
    deliver_capability_fixture(wire, "backend_completed")

    assert_receive {:vxpipe_usage_observations, ^capability, backend}
    assert Enum.map(backend, & &1.measurement.quantity) == [3, 2]
    assert Enum.all?(backend, &(&1.provider.model == "gpt-5.6"))
    assert Enum.all?(backend, &(&1.capability == :model_inference))
    assert Enum.all?(backend, &(&1.measurement.provenance == :provider_reported))
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp deny_agent_audio do
    %Effective{
      audio_routes: %{"agent1" => MapSet.new()},
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp assert_replacement_speaks(capability, replacement) do
    deliver_capability_fixture(replacement, "agent_hello")
    tone = :binary.copy(<<0, 16>>, 480)
    silence = :binary.copy(<<0, 0>>, 480 * 2)

    TestGPTLiveTransport.deliver_sync(replacement, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone <> silence)
    })

    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent1", turn, _}, 1_000
    assert_receive {:test_audio_output, sink, _frame}, 1_000
    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    TestAudioOutputSink.playback_progress(sink, 60, 60)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent1", "Hello", ^turn, _, _, _},
                   1_000
  end

  defp start_ready_capability(options \\ []) do
    {:ok, config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {:ok, private} =
      PrivateInit.open(
        [config: config, wire_module: TestGPTLiveTransport, wire_options: [observer: self()]] ++
          options,
        5_000
      )

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: self(),
             agent_id: "agent1",
             human_id: "human1",
             provider: {GPTLiveSession, [backend_model: "gpt-5.6"]},
             provider_private: private,
             sink: sink,
             frame_identity: %{},
             caller_source: :sts,
             policy: unrestricted()
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:test_gpt_live_started, wire, _connection}, 5_000

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.start", "session" => %{"store" => false}}}

    refute_received {:vxpipe_sts_ready, ^capability}

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    {capability, wire}
  end

  defp deliver_fixture(wire, name) do
    TestGPTLiveTransport.deliver_sync(wire, fixture_entry(@delegation_fixture, name)["event"])
  end

  defp deliver_capability_fixture(wire, name) do
    case fixture_entry(@capability_fixture, name) do
      %{"event" => event} -> TestGPTLiveTransport.deliver_sync(wire, event)
      %{"raw" => payload} -> TestGPTLiveTransport.deliver_raw(wire, payload)
    end
  end

  defp fixture_entry(path, name) do
    path
    |> File.stream!()
    |> Stream.map(&JSON.decode!/1)
    |> Enum.find_value(fn %{"name" => fixture_name} = entry ->
      if fixture_name == name, do: entry
    end)
  end
end
