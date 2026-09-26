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
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000

    assert :ok = SpeechToSpeech.push_audio(capability, "human1", <<1, 0>>)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "Hi",
      "start_ms" => 0,
      "end_ms" => 20
    })

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "Hi"}}},
                   1_000

    input_silence = :binary.copy(<<0, 0>>, div(24_000 * 800, 1_000))
    assert :ok = SpeechToSpeech.push_audio(capability, "human1", input_silence)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "Hi", final: true}}},
                   1_000

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_transcript.delta",
      "delta" => "Hello",
      "start_ms" => 100,
      "end_ms" => 120
    })

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

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.closed", "reason" => "expired"})
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

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.usage.updated",
      "usage" => %{"seconds" => 1.25}
    })

    assert_receive {:vxpipe_usage_observations, ^capability, [voice]}
    assert voice.capability == :speech_to_speech
    assert voice.provider.model == "gpt-live-1"
    assert voice.measurement.quantity == 1_250
    assert voice.measurement.provenance == :provider_reported

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.usage.updated",
      "usage" => %{"seconds" => 1.25}
    })

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.usage.updated",
      "usage" => %{"seconds" => 1.5}
    })

    assert_receive {:vxpipe_usage_observations, ^capability, [voice_delta]}
    assert voice_delta.measurement.quantity == 250

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.delegation.created",
      "delegation" => %{"id" => "d", "target" => "responses", "response_id" => "r"}
    })

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "response.event",
      "delegation_id" => "d",
      "event" => %{
        "type" => "response.completed",
        "response" => %{"id" => "r", "usage" => %{"input_tokens" => 3, "output_tokens" => 2}}
      }
    })

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
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    {capability, wire}
  end

  defp deliver_fixture(wire, name) do
    event =
      @delegation_fixture
      |> File.stream!()
      |> Stream.map(&JSON.decode!/1)
      |> Enum.find_value(fn %{"name" => fixture_name, "event" => event} ->
        if fixture_name == name, do: event
      end)

    TestGPTLiveTransport.deliver(wire, event)
  end
end
