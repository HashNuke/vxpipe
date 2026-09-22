defmodule Vxpipe.CallEngine.Capability.GoogleSTSControllerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Speech.{Event, PrivateInit, Session}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestGoogleSTSTransport}
  alias Vxpipe.Providers.Google.{STS, STSSession}

  test "caller activity end streams twenty credited chunks before model turn completion" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, content(%{"outputTranscription" => %{"text" => "Hello "}}))
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)

    for index <- 1..20 do
      deliver(context, audio_message(index))
      assert_audio(context, index)
    end

    deliver(context, content(%{"outputTranscription" => %{"text" => "world"}}))
    finish_generation(context)
    deliver(context, content(%{"outputTranscription" => %{"text" => "LATE"}}))
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _}
    finish_playback(context, turn, "Hello world", 400)
  end

  test "text and completed audio received before caller end survive real admission" do
    context = start_controller()
    turn = start_caller(context)

    deliver(context, content(%{"outputTranscription" => %{"text" => "Early "}}))

    deliver(
      context,
      audio_message(1)
      |> Map.update!("serverContent", fn body ->
        Map.merge(body, %{
          "outputTranscription" => %{"text" => "reply"},
          "generationComplete" => true
        })
      end)
    )

    refute_received {:test_audio_output, _, _}
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    assert_audio(context, 1)
    sink = context.sink
    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    finish_playback(context, turn, "Early reply", 20)
  end

  test "model completion is not caller completion and activity end does not finalize partial text" do
    context = start_controller()
    turn = start_caller(context)
    capability = context.capability
    deliver(context, content(%{"inputTranscription" => %{"text" => "partial"}}))
    deliver(context, content(%{"turnComplete" => true}))
    refute_received {:vxpipe_sts_input_event, ^capability, %{event: %Event{kind: :turn_ended}}}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _}
    deliver(context, activity("ACTIVITY_END"))

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %Event{kind: :turn_ended, turn_ref: ^turn, text: ""}}}

    assert_started(context, turn)
  end

  test "duplicate caller boundaries cannot replace or queue the admitted reply" do
    context = start_controller()
    turn = start_caller(context)
    capability = context.capability
    deliver(context, activity("ACTIVITY_START"))
    refute_received {:vxpipe_sts_speech_started, ^capability, _, _}
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    deliver(context, activity("ACTIVITY_END"))
    deliver(context, content(%{"turnComplete" => true}))
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _}
    assert :sys.get_state(capability).pending_turns == []
  end

  test "aggregate transcription overflow fails without publishing or reconnecting" do
    context = start_controller()
    _turn = start_caller(context)
    provider = context.provider
    monitor = Process.monitor(provider)

    deliver(
      context,
      content(%{"outputTranscription" => %{"text" => String.duplicate("x", 65_536)}})
    )

    TestGoogleSTSTransport.deliver(
      context.wire,
      JSON.encode!(content(%{"outputTranscription" => %{"text" => "x"}}))
    )

    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :session_failed}}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "a settled reply cannot contribute text to the next reply" do
    context = start_controller()

    for {text, index} <- [{"FIRST", 1}, {"SECOND", 2}] do
      turn = start_caller(context)
      deliver(context, content(%{"outputTranscription" => %{"text" => text}}))
      deliver(context, activity("ACTIVITY_END"))
      assert_started(context, turn)
      deliver(context, audio_message(index))
      assert_audio(context, index)
      finish_generation(context)
      finish_playback(context, turn, text, 20)
      _ = :sys.get_state(context.provider)
    end
  end

  test "ordinary model text and thought parts are not spoken transcription" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)

    deliver(
      context,
      content(%{
        "outputTranscription" => %{"text" => "Spoken"},
        "modelTurn" => %{
          "parts" => [%{"text" => "Spoken"}, %{"text" => "private thought", "thought" => true}]
        }
      })
    )

    deliver(context, audio_message(1))
    assert_audio(context, 1)
    finish_generation(context)
    finish_playback(context, turn, "Spoken", 20)
  end

  test "handle renewal waits for model turn completion even after local playback" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    deliver(context, content(%{"outputTranscription" => %{"text" => "Reply"}}))
    deliver(context, audio_message(1))
    assert_audio(context, 1)
    finish_generation(context)
    finish_playback(context, turn, "Reply", 20)
    _ = :sys.get_state(context.provider)

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "before-model-end", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    deliver(context, content(%{"turnComplete" => true}))
    refute_received {:test_google_sts_started, _, _}

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "after-model-end", "resumable" => true}
    })

    assert_receive {:test_google_sts_started, pending, _}, 1_000
    assert_receive {:test_google_sts_control, ^pending, setup}, 1_000
    assert JSON.decode!(setup)["setup"]["sessionResumption"] == %{"handle" => "after-model-end"}
    TestGoogleSTSTransport.deliver(pending, JSON.encode!(%{"setupComplete" => %{}}))
    _ = :sys.get_state(pending)
    _ = :sys.get_state(context.provider)
    refute_received {:test_google_sts_audio, ^pending, _}
    refute_received {:test_google_sts_control, ^pending, _}
  end

  test "model text alone cannot substitute for missing audio transcription" do
    context = start_controller()
    turn = start_caller(context)
    capability = context.capability
    monitor = Process.monitor(capability)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "Not audio text"}]}}))
    deliver(context, audio_message(1))
    assert_audio(context, 1)

    TestGoogleSTSTransport.deliver(
      context.wire,
      JSON.encode!(content(%{"generationComplete" => true}))
    )

    assert_receive {:vxpipe_sts_unavailable, ^capability, :output_transcript_missing}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :output_transcript_missing}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _}
  end

  for admitted? <- [false, true] do
    test "#{if admitted?, do: "admitted", else: "pre-admission"} interrupted text cannot leak into a fresh reply" do
      context = start_controller()
      old_turn = start_caller(context)
      deliver(context, content(%{"outputTranscription" => %{"text" => "OLD"}}))

      if unquote(admitted?) do
        deliver(context, activity("ACTIVITY_END"))
        assert_started(context, old_turn)
        deliver(context, audio_message(1))
        assert_audio(context, 1)
        assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
        deliver(context, content(%{"outputTranscription" => %{"text" => "LATE"}}))
      end

      deliver(context, content(%{"interrupted" => true}))
      deliver(context, content(%{"turnComplete" => true}))
      turn = start_caller(context)
      assert turn != old_turn
      deliver(context, activity("ACTIVITY_END"))
      assert_started(context, turn)
      deliver(context, content(%{"outputTranscription" => %{"text" => "NEW"}}))
      deliver(context, audio_message(2))
      assert_audio(context, 2)
      finish_generation(context)
      finish_playback(context, turn, "NEW", 20)
      refute_received {:vxpipe_sts_turn_completed, _, _, ^old_turn}
    end
  end

  for {mode, turn_control} <- [provider: "provider", typed: "provider", external: "external"] do
    test "#{mode} overlapping model lifetimes cannot create a false idle checkpoint" do
      mode = unquote(mode)
      context = start_controller(unquote(turn_control))
      first = begin_reply(context, mode)
      complete_reply(context, first, "FIRST", 1)
      second = begin_reply(context, mode)
      deliver(context, content(%{"turnComplete" => true}))
      complete_reply(context, second, "SECOND", 2)

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "ambiguous-model-end", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert :sys.get_state(context.provider).wire == context.wire
      refute_received {:test_google_sts_started, _, _}
      deliver(context, content(%{"turnComplete" => true}))

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "still-ambiguous", "resumable" => true}
      })

      assert :sys.get_state(context.provider).wire == context.wire
      refute_received {:test_google_sts_started, _, _}
      provider = context.provider
      monitor = Process.monitor(provider)
      TestGoogleSTSTransport.disconnect(context.wire)
      assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :session_failed}}, 1_000
      refute_received {:test_google_sts_started, _, _}
    end
  end

  defp begin_reply(context, :provider) do
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    turn
  end

  defp begin_reply(context, mode) do
    if mode == :typed do
      assert :ok = SpeechToSpeech.push_text(context.capability, "synthetic input")
    else
      assert :ok = SpeechToSpeech.input_activity(context.capability, :started)
      assert :ok = SpeechToSpeech.input_activity(context.capability, :ended)
    end

    capability = context.capability
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn}, 1_000
    turn
  end

  defp complete_reply(context, turn, text, index) do
    deliver(context, content(%{"outputTranscription" => %{"text" => text}}))
    deliver(context, audio_message(index))
    assert_audio(context, index)
    finish_generation(context)
    finish_playback(context, turn, text, 20)
    _ = :sys.get_state(context.provider)
  end

  defp start_controller(turn_control \\ "provider") do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, config} =
             STS.new(api_key: "synthetic-google-controller-key", turn_control: turn_control)

    assert {:ok, private} =
             PrivateInit.open(
               [
                 config: config,
                 wire_module: TestGoogleSTSTransport,
                 wire_options: [observer: self()]
               ],
               5_000
             )

    tree =
      start_supervised!(
        {SpeechToSpeech.Tree,
         owner: self(),
         agent_id: "agent",
         human_id: "caller",
         provider: {STSSession, [turn_control: turn_control]},
         provider_private: private,
         sink: sink,
         frame_identity: %{}}
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:test_google_sts_started, wire, _}, 1_000
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(%{"setupComplete" => %{}}))
    assert_receive {:vxpipe_sts_ready, ^capability}, 1_000
    provider = Session.provider(:sys.get_state(capability).session)
    %{capability: capability, provider: provider, sink: sink, wire: wire}
  end

  defp start_caller(context) do
    deliver(context, activity("ACTIVITY_START"))
    capability = context.capability
    assert_receive {:vxpipe_sts_speech_started, ^capability, "agent", turn}, 1_000
    turn
  end

  defp assert_started(context, turn) do
    capability = context.capability
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^turn}, 1_000
  end

  defp deliver(context, message) do
    TestGoogleSTSTransport.deliver(context.wire, JSON.encode!(message))
    _ = :sys.get_state(context.wire)
    _ = :sys.get_state(context.provider)
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.provider)
  end

  defp assert_audio(context, index) do
    sink = context.sink
    assert_receive {:test_audio_output, ^sink, frame}, 1_000
    assert frame.payload == :binary.copy(<<index::little-signed-16>>, 480)
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.provider)
  end

  defp finish_generation(context) do
    deliver(context, content(%{"generationComplete" => true}))
    sink = context.sink
    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
  end

  defp finish_playback(context, turn, expected, duration) do
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, duration, duration)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    capability = context.capability

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, "agent", ^expected, ^turn,
                    ^duration, _},
                   1_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^turn}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _}
  end

  defp activity(type), do: %{"voiceActivity" => %{"type" => type}}
  defp content(body), do: %{"serverContent" => body}

  defp audio_message(index) do
    content(%{
      "modelTurn" => %{
        "parts" => [
          %{
            "inlineData" => %{
              "mimeType" => "audio/pcm;rate=24000",
              "data" => Base.encode64(:binary.copy(<<index::little-signed-16>>, 480))
            }
          }
        ]
      }
    })
  end
end
