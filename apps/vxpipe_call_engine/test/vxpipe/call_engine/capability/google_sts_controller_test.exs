defmodule Vxpipe.CallEngine.Capability.GoogleSTSControllerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Speech.{Event, PrivateInit, Session}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestGoogleSTSTransport}
  alias Vxpipe.Providers.Google.{STS, STSSession}

  for profile <- [false, true] do
    test "fixed Gemini opening without text completes after physical playback with response-start #{profile}" do
      context = start_controller("provider", response_start?: unquote(profile))
      capability = context.capability
      sink = context.sink
      assert :ok = SpeechToSpeech.begin_opening(capability, {:fixed, "Alpha."})
      deliver(context, audio_message(1))
      deliver(context, content(%{"generationComplete" => true}))
      refute_received {:test_audio_output, ^sink, _}
      deliver(context, interaction_end("IDLE"))
      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", opening, _}, 1_000
      assert_audio(context, 1)
      assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
      refute_received {:vxpipe_sts_turn_completed, ^capability, _, _, _}
      assert :sys.get_state(capability).opening_playing?
      assert :ok = TestAudioOutputSink.playback_progress(sink, 20, 20)
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^opening, _}, 1_000
      refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
      refute :sys.get_state(capability).opening_playing?

      assert :ok = SpeechToSpeech.push_text(capability, "Continue")
      deliver(context, content(%{"outputTranscription" => %{"text" => "NEXT"}}))
      deliver(context, audio_message(2))
      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", next, _}, 1_000
      assert next != opening
      assert_audio(context, 2)
      finish_generation(context)
      finish_playback(context, next, "NEXT", 20)
    end
  end

  for {mode, turn_control} <- [provider: "provider", external: "external", typed: "provider"] do
    test "#{mode} first response needs model PCM and has identity independent of its caller" do
      mode = unquote(mode)
      context = start_controller(unquote(turn_control), response_start?: true)
      capability = context.capability
      caller = submit_response_input(context, mode)
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}

      deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST RESPONSE"}}))
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
      deliver(context, audio_message(1))

      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
      assert response != caller
      assert_audio(context, 1)
      finish_generation(context)
      finish_playback(context, response, "FIRST RESPONSE", 20)
      deliver(context, interaction_end("IDLE"))
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    end
  end

  for timing <- [:after_playback, :before_playback] do
    test "a second model response #{timing} owns distinct credited audio and text" do
      context = start_controller("provider", response_start?: true)
      capability = context.capability
      sink = context.sink
      caller = submit_response_input(context, :provider)
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
      deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST RESPONSE"}}))
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
      deliver(context, audio_message(1))
      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
      assert first != caller
      assert_audio(context, 1)
      finish_generation(context)

      if unquote(timing) == :after_playback,
        do: finish_playback(context, first, "FIRST RESPONSE", 20)

      deliver(context, interaction_end("IN_PROGRESS"))
      deliver(context, content(%{"outputTranscription" => %{"text" => "SECOND RESPONSE"}}))
      deliver(context, audio_message(2))
      deliver(context, content(%{"generationComplete" => true}))

      if unquote(timing) == :before_playback do
        refute_received {:test_audio_output, ^sink, _}
        refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
        finish_playback(context, first, "FIRST RESPONSE", 20)
      end

      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", second, _}, 1_000
      assert second != first
      assert_audio(context, 2)
      assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
      finish_playback(context, second, "SECOND RESPONSE", 20)
      deliver(context, interaction_end("IDLE"))
      refute_received {:vxpipe_sts_speech_started, ^capability, _, _}
      refute_received {:test_google_sts_control, _, _}
      assert :sys.get_state(context.provider).caller == nil
    end
  end

  test "opted-in renewal waits for retained response playback after model idle" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    settle_audio_caller(context)
    deliver(context, content(%{"outputTranscription" => %{"text" => "REPLY"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
    assert_audio(context, 1)
    finish_generation(context)
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "pending-playback", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    refute_received {:test_google_sts_started, _, _}
    finish_playback(context, response, "REPLY", 20)
    assert_receive {:test_google_sts_started, pending, _}, 1_000
    assert_receive {:test_google_sts_control, ^pending, setup}, 1_000

    assert JSON.decode!(setup)["setup"]["sessionResumption"] ==
             %{"handle" => "pending-playback"}
  end

  test "opted-in renewal waits for both overlapping response playback obligations" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    sink = context.sink
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    settle_audio_caller(context)
    deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
    assert_audio(context, 1)
    finish_generation(context)
    deliver(context, interaction_end("IN_PROGRESS"))

    deliver(context, content(%{"outputTranscription" => %{"text" => "SECOND"}}))
    deliver(context, audio_message(2))
    deliver(context, content(%{"generationComplete" => true}))
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "both-pending", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    refute_received {:test_google_sts_started, _, _}
    finish_playback(context, first, "FIRST", 20)
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", second, _}, 1_000
    assert second != first
    assert_audio(context, 2)
    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    refute_received {:test_google_sts_started, _, _}
    finish_playback(context, second, "SECOND", 20)
    assert_receive {:test_google_sts_started, pending, _}, 1_000
    assert_receive {:test_google_sts_control, ^pending, setup}, 1_000
    assert JSON.decode!(setup)["setup"]["sessionResumption"] == %{"handle" => "both-pending"}
  end

  test "opted-in settled idle interaction accepts a new origin on the same wire" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    settle_audio_caller(context)
    deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
    assert_audio(context, 1)
    finish_generation(context)
    finish_playback(context, first, "FIRST", 20)
    deliver(context, interaction_end("IDLE"))

    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    second_context = :sys.get_state(context.provider).interaction_context
    assert is_reference(second_context) and second_context != first_context

    deliver(context, content(%{"outputTranscription" => %{"text" => "SECOND"}}))
    deliver(context, audio_message(2))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", second, _}, 1_000
    assert second != first
    assert_audio(context, 2)
    finish_generation(context)
    finish_playback(context, second, "SECOND", 20)
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
  end

  test "opted-in model idle cannot cut over audio lacking its independent caller final" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert_new_origin_busy(context, first_context)
  end

  test "opted-in late A caller final releases audio-origin cutover without replay" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    caller = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert_new_origin_busy(context, first_context)
    deliver(context, content(%{"inputTranscription" => %{"text" => "A CALLER"}}))
    assert %{caller: nil, awaiting_audio_final?: false} = :sys.get_state(context.provider)

    refute_received {:vxpipe_sts_input_event, ^capability,
                     %{event: %Event{kind: :input_transcript, turn_ref: ^caller}}}

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    assert :sys.get_state(context.provider).interaction_context != first_context
  end

  test "opted-in A1 final cannot clear A2 PCM sent after A1 activity end" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    caller = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    final_caller(context, caller, "A1 CALLER")
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert_new_origin_busy(context, first_context)
  end

  test "opted-in A2 final clears only its retained audio obligation" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    first = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "first thought"}]}}))
    deliver(context, interaction_end("IDLE"))
    final_caller(context, first, "A1 CALLER")
    assert :sys.get_state(context.provider).awaiting_audio_final?

    second = start_caller(context)
    final_caller(context, second, "A2 CALLER")
    deliver(context, activity("ACTIVITY_END"))
    assert :sys.get_state(context.provider).awaiting_audio_final? == false
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    assert :sys.get_state(context.provider).interaction_context != first_context
  end

  test "opted-in idle cutover accepts a new typed input origin" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    settle_audio_caller(context)
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))
    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())

    assert :ok = SpeechToSpeech.push_text(capability, "NEXT")
    assert_receive {:test_google_sts_control, ^wire, payload}, 1_000
    assert JSON.decode!(payload) == %{"realtimeInput" => %{"text" => "NEXT"}}
    assert :sys.get_state(context.provider).interaction_context != first_context
    deliver(context, content(%{"outputTranscription" => %{"text" => "TYPED REPLY"}}))
    deliver(context, audio_message(3))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
    assert_audio(context, 3)
    finish_generation(context)
    finish_playback(context, response, "TYPED REPLY", 20)
    deliver(context, interaction_end("IDLE"))
  end

  test "opted-in idle cutover accepts new external activity without replay" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _start}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, _end}, 1_000
    deliver(context, content(%{"inputTranscription" => %{"text" => "FIRST CALLER"}}))
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))
    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.release(capability, make_ref())

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _new_start}, 1_000
    second_context = :sys.get_state(context.provider).interaction_context
    assert second_context != first_context
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, _new_end}, 1_000
    deliver(context, content(%{"inputTranscription" => %{"text" => "SECOND CALLER"}}))
    deliver(context, content(%{"outputTranscription" => %{"text" => "EXTERNAL REPLY"}}))
    deliver(context, audio_message(4))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
    assert_audio(context, 4)
    finish_generation(context)
    finish_playback(context, response, "EXTERNAL REPLY", 20)
    deliver(context, interaction_end("IDLE"))
  end

  test "opted-in in-progress model work blocks a new wire origin" do
    context = start_controller("provider", response_start?: true)
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(context.capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    deliver(context, interaction_end("IN_PROGRESS"))
    assert_new_origin_busy(context, first_context)
  end

  test "opted-in retained playback blocks a new wire origin despite model idle" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", _first, _}, 1_000
    assert_audio(context, 1)
    finish_generation(context)
    deliver(context, interaction_end("IDLE"))
    assert_new_origin_busy(context, first_context)
  end

  test "opted-in pending tool blocks a new wire origin despite model idle" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context

    deliver(context, %{
      "toolCall" => %{
        "functionCalls" => [%{"id" => "cutover-tool", "name" => "lookup", "args" => %{}}]
      }
    })

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent",
                    %{event: %Event{kind: :tool_call}}},
                   1_000

    deliver(context, interaction_end("IDLE"))
    assert_new_origin_busy(context, first_context)
  end

  test "opted-in ambiguous interrupted caller blocks a new wire origin" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    deliver(context, content(%{"interrupted" => true}))
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, _}, 1_000
    deliver(context, content(%{"inputTranscription" => %{"text" => "FINAL"}}))
    deliver(context, interaction_end("IDLE"))
    assert :sys.get_state(context.provider).resumption_ambiguous?
    assert_new_origin_busy(context, first_context)
  end

  test "opted-in fresh activity end cannot cut over a completed interaction" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _start}, 1_000
    %{caller: %{turn_ref: caller}} = :sys.get_state(context.provider)
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, _end}, 1_000
    final_caller(context, caller, "CALLER")
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))
    assert :ok = SpeechToSpeech.release(capability, make_ref())

    assert {:error, :busy} = SpeechToSpeech.input_activity(capability, :ended)
    _ = :sys.get_state(wire)
    refute_received {:test_google_sts_control, ^wire, _}
    assert :sys.get_state(context.provider).interaction_context == first_context
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    assert :sys.get_state(context.provider).interaction_context != first_context
  end

  test "opted-in renewal request blocks a new wire origin despite model idle" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    first_context = :sys.get_state(context.provider).interaction_context
    deliver(context, interaction_end("IDLE"))
    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).renew_requested?
    assert_new_origin_busy(context, first_context)
  end

  @tag :gemini_longevity
  test "pending rotation accepts same-context PCM while a typed turn is open" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_text(capability, "FIRST")
    assert_receive {:test_google_sts_control, ^wire, _text}, 1_000
    deliver(context, interaction_end("IDLE"))
    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert %{renew_requested?: true, input_turn: turn} = :sys.get_state(context.provider)
    assert is_reference(turn)

    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
  end

  @tag :gemini_longevity
  test "pending rotation preserves external caller activity boundaries" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _started}, 1_000
    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).renew_requested?

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    _ = :sys.get_state(wire)
    refute_received {:test_google_sts_control, ^wire, _}
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, _ended}, 1_000
  end

  for status <- [:missing, "IDLE"] do
    @tag :gemini_live_wire_lifecycle
    test "completed #{status} exchange resumes with the latest periodic session handle" do
      context = start_controller("provider", response_start?: true)
      capability = context.capability

      deliver(context, %{
        "sessionResumptionUpdate" => %{
          "newHandle" => "periodic-session-token",
          "resumable" => true
        }
      })

      assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
      origin = :sys.get_state(context.provider).interaction_context
      settle_audio_caller(context)
      deliver(context, content(%{"outputTranscription" => %{"text" => "REPLY"}}))
      deliver(context, audio_message(1))
      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
      assert_audio(context, 1)
      finish_generation(context)
      deliver(context, interaction_end(unquote(status)))
      finish_playback(context, response, "REPLY", 20)
      if unquote(status) == :missing, do: refute(STSSession.input_quiescent?(context.provider))
      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, pending, _}, 1_000
      assert_receive {:test_google_sts_control, ^pending, setup}, 1_000

      assert JSON.decode!(setup)["setup"]["sessionResumption"] ==
               %{"handle" => "periodic-session-token"}

      assert :sys.get_state(context.provider).interaction_context == origin
    end
  end

  for {mode, status} <- [{"external", "IDLE"}, {"provider", "IDLE"}, {"provider", :missing}] do
    @tag :gemini_longevity
    @tag :gemini_live_wire_lifecycle
    test "a clean #{mode}/#{status} exchange clears earlier resumption ambiguity" do
      mode = unquote(mode)
      context = start_controller(mode, response_start?: true)
      capability = context.capability
      caller_boundary(context, mode, :started)
      deliver(context, content(%{"interrupted" => true}))
      caller_boundary(context, mode, :ended)
      deliver(context, content(%{"inputTranscription" => %{"text" => "OLD"}}))
      deliver(context, interaction_end("IDLE"))
      assert :sys.get_state(context.provider).resumption_ambiguous?

      caller_boundary(context, mode, :started)
      caller_boundary(context, mode, :ended)
      %{caller: %{turn_ref: caller}} = :sys.get_state(context.provider)
      final_caller(context, caller, "CLEAN")
      deliver(context, content(%{"outputTranscription" => %{"text" => "CLEAN REPLY"}}))
      deliver(context, audio_message(1))
      assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
      assert_audio(context, 1)
      finish_generation(context)
      deliver(context, interaction_end(unquote(status)))
      finish_playback(context, response, "CLEAN REPLY", 20)
      refute :sys.get_state(context.provider).resumption_ambiguous?

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "after-clean-exchange", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, pending, _connection}, 1_000
      assert_receive {:test_google_sts_control, ^pending, setup}, 1_000

      assert JSON.decode!(setup)["setup"]["sessionResumption"] ==
               %{"handle" => "after-clean-exchange"}
    end
  end

  test "opted-in late idle cannot permit C before B has model activity" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    settle_audio_caller(context)
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}, 1_000
    second_context = :sys.get_state(context.provider).interaction_context

    deliver(context, interaction_end("IDLE"))
    assert_new_origin_busy(context, second_context)
  end

  test "opted-in text-only model work retires without a public speech turn" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    deliver(context, content(%{"outputTranscription" => %{"text" => "private thought"}}))
    deliver(context, content(%{"generationComplete" => true}))
    deliver(context, interaction_end("IDLE"))

    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
    assert :sys.get_state(context.provider).responses.records == %{}
  end

  test "opted-in active external hold fails closed without sending an ordinary end" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _activity_start}, 1_000
    deliver(context, audio_message(1))
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    refute_received {:test_google_sts_control, ^wire, _}
  end

  test "active external caller activity cannot survive hold without a reset proof" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _activity_start}, 1_000

    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = SpeechToSpeech.hold(capability)
    assert_receive {:vxpipe_sts_unavailable, ^capability, :unsafe_hold}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :unsafe_hold}
    assert {:error, :unavailable} = SpeechToSpeech.release(capability, make_ref())
  end

  test "opted-in response drains PCM arriving after its first playback credit" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", _response, _}, 1_000
    assert_audio(context, 1)

    for index <- 2..18 do
      deliver(context, audio_message(index))
      assert_audio(context, index)
    end
  end

  test "opted-in standalone model interruption isolates the next response without a caller turn" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    assert :sys.get_state(context.provider).input_turn == nil
    deliver(context, content(%{"outputTranscription" => %{"text" => "OLD"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
    assert_audio(context, 1)

    deliver(context, content(%{"interrupted" => true}))
    deliver(context, content(%{"outputTranscription" => %{"text" => "NEW"}}))
    deliver(context, audio_message(2))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", second, _}, 1_000
    assert second != first
    assert_audio(context, 2)

    assert {:ok, %{text: "NEW"}} =
             Vxpipe.Providers.Google.STSResponses.fetch(
               :sys.get_state(context.provider).responses,
               second
             )
  end

  test "interrupting retained playback does not interrupt a newer wire response" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    deliver(context, content(%{"outputTranscription" => %{"text" => "FIRST"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
    assert_audio(context, 1)
    finish_generation(context)
    deliver(context, interaction_end("IN_PROGRESS"))
    deliver(context, audio_message(2))
    assert :sys.get_state(context.provider).responses.wire != first

    assert :ok = STSSession.interrupt(context.provider, first)
    refute_received {:test_google_sts_control, ^wire, _}
  end

  test "genuine Google caller onset fences playback and survives the server interruption" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    wire = context.wire
    submit_response_input(context, :typed)
    assert_receive {:test_google_sts_control, ^wire, _input}
    deliver(context, content(%{"outputTranscription" => %{"text" => "ONE TWO THREE"}}))
    deliver(context, audio_message(1))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", first, _}, 1_000
    assert_audio(context, 1)

    caller = start_caller(context)
    assert_receive {:vxpipe_sts_interrupted, ^capability, "agent", ^first, _, _, _}, 1_000
    refute_received {:test_google_sts_control, ^wire, _cancel}
    deliver(context, content(%{"outputTranscription" => %{"text" => "LATE OLD"}}))
    deliver(context, audio_message(2))
    refute_received {:test_audio_output, _, _}
    deliver(context, content(%{"interrupted" => true}))
    final_caller(context, caller, "STOP COUNTING")
    deliver(context, activity("ACTIVITY_END"))
    deliver(context, content(%{"outputTranscription" => %{"text" => "STOPPED"}}))
    deliver(context, audio_message(3))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", second, _}, 1_000
    assert second != first
    assert_audio(context, 3)
    finish_generation(context)
    finish_playback(context, second, "STOPPED", 20)
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, "LATE OLD", _, _, _, _}
  end

  test "manual interruption of the current Google response closes its allocation without old history" do
    context = start_controller()
    capability = context.capability
    wire = context.wire
    turn = begin_reply(context, :provider)
    deliver(context, content(%{"outputTranscription" => %{"text" => "UNPLAYED OLD"}}))
    deliver(context, audio_message(1))
    assert_audio(context, 1)
    provider_monitor = Process.monitor(context.provider)
    capability_monitor = Process.monitor(capability)

    assert {:ok, 0} = SpeechToSpeech.interrupt(capability)
    assert_receive {:DOWN, ^provider_monitor, :process, _, _}, 1_000
    assert_receive {:DOWN, ^capability_monitor, :process, _, _}, 1_000
    refute_received {:test_google_sts_control, ^wire, _}

    TestGoogleSTSTransport.deliver(
      wire,
      JSON.encode!(content(%{"outputTranscription" => %{"text" => "LATE OLD"}}))
    )

    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, ^turn, _, _, _}
    refute_received {:vxpipe_sts_turn_completed, ^capability, _, ^turn, _}
  end

  test "opted-in tool call cannot strand a response behind its caller end" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    caller = start_caller(context)

    deliver(context, %{
      "toolCall" => %{
        "functionCalls" => [%{"id" => "lookup-1", "name" => "lookup", "args" => %{}}]
      }
    })

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent",
                    %{event: %Event{kind: :tool_call, call_ref: call, turn_ref: tool_turn}}},
                   1_000

    assert tool_turn != caller
    deliver(context, content(%{"outputTranscription" => %{"text" => "TOOL REPLY"}}))
    deliver(context, audio_message(1))
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    final_caller(context, caller, "CALLER")
    deliver(context, activity("ACTIVITY_END"))
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", response, _}, 1_000
    assert response == tool_turn
    assert_audio(context, 1)
    assert :ok = SpeechToSpeech.send_tool_result(capability, call, %{"value" => 1})
    assert :sys.get_state(capability).pending_turns == []
  end

  test "opted-in tool-only response needs model content and fresh idle after its result" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    settle_audio_caller(context)

    deliver(context, %{
      "toolCall" => %{
        "functionCalls" => [%{"id" => "tool-only", "name" => "lookup", "args" => %{}}]
      }
    })

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent",
                    %{event: %Event{kind: :tool_call, call_ref: call}}},
                   1_000

    deliver(context, content(%{"generationComplete" => true}))
    deliver(context, interaction_end("IDLE"))
    assert :sys.get_state(context.provider).responses.records == %{}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "tool-pending", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    refute_received {:test_google_sts_started, _, _}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call, %{"value" => 1})
    assert :sys.get_state(context.provider).pending_tools == %{}

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "before-new-idle", "resumable" => true}
    })

    refute_received {:test_google_sts_started, _, _}
    deliver(context, interaction_end("IDLE"))
    refute_received {:test_google_sts_started, _, _}
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "private thought"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert_receive {:test_google_sts_started, pending, _}, 1_000
    assert_receive {:test_google_sts_control, ^pending, setup}, 1_000
    assert JSON.decode!(setup)["setup"]["sessionResumption"] == %{"handle" => "before-new-idle"}
  end

  test "opted-in interrupted caller cannot renew from a possibly old idle boundary" do
    context = start_controller("external", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    deliver(context, content(%{"interrupted" => true}))
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    deliver(context, content(%{"inputTranscription" => %{"text" => "FINAL"}}))
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "possibly-old", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).resumption_ambiguous?
    refute_received {:test_google_sts_started, _, _}
  end

  test "opted-in provider-ended caller also rejects an interrupted stale idle handle" do
    context = start_controller("provider", response_start?: true)
    capability = context.capability
    assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    caller = start_caller(context)
    deliver(context, content(%{"interrupted" => true}))
    final_caller(context, caller, "FINAL")
    deliver(context, activity("ACTIVITY_END"))
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "possibly-old", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).resumption_ambiguous?
    refute_received {:test_google_sts_started, _, _}
  end

  test "one genuinely new realtime text input produces one credited controller reply" do
    context = start_controller()
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.push_text(capability, "typed input")
    assert_receive {:test_google_sts_control, ^wire, payload}, 1_000
    assert JSON.decode!(payload) == %{"realtimeInput" => %{"text" => "typed input"}}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn, _}, 1_000
    complete_reply(context, turn, "TYPED REPLY", 1)
    refute_received {:test_google_sts_control, ^wire, _}
    refute_received {:vxpipe_sts_speech_started, ^capability, _, _}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
  end

  for status <- ["IN_PROGRESS", "INTERACTION_STATUS_UNSPECIFIED", "REQUIRES_ACTION"] do
    test "model end with #{status} cannot authorize renewal without explicit interaction idle" do
      context = start_controller()
      turn = begin_reply(context, :provider)
      complete_reply(context, turn, "FIRST RESPONSE", 1)
      deliver(context, interaction_end(unquote(status)))

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "not-idle", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert :sys.get_state(context.provider).wire == context.wire
      refute_received {:test_google_sts_started, _, _}
      deliver(context, interaction_end("IDLE"))

      assert_receive {:test_google_sts_started, _, _}, 1_000
    end
  end

  test "an accepted tool result cannot reuse idle evidence from before its submission" do
    context = start_controller()
    capability = context.capability
    turn = begin_reply(context, :provider)

    deliver(context, %{
      "toolCall" => %{
        "functionCalls" => [%{"id" => "profile-tool", "name" => "lookup", "args" => %{}}]
      }
    })

    assert_receive {:vxpipe_sts_tool_event, ^capability, "agent",
                    %{event: %Event{kind: :tool_call, call_ref: call}}},
                   1_000

    complete_reply(context, turn, "BEFORE TOOL RESULT", 1)
    deliver(context, interaction_end("IDLE"))
    assert :ok = SpeechToSpeech.send_tool_result(capability, call, %{"value" => "result"})

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "after-tool", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    deliver(context, interaction_end("IDLE"))
    refute_received {:test_google_sts_started, _, _}
    deliver(context, content(%{"modelTurn" => %{"parts" => [%{"text" => "fresh model work"}]}}))
    deliver(context, interaction_end("IDLE"))

    assert_receive {:test_google_sts_started, _, _}, 1_000
  end

  for prior <- [:pristine, :settled] do
    test "accepted PCM at #{prior} idle cannot renew before its caller onset arrives" do
      context = start_controller()
      capability = context.capability
      wire = context.wire

      if unquote(prior) == :settled do
        turn = begin_reply(context, :provider)
        complete_reply(context, turn, "PREVIOUS", 1)
        deliver(context, interaction_end("IDLE"))
      end

      assert :ok = SpeechToSpeech.push_audio(capability, "caller", <<5, 0>>)
      assert_receive {:test_google_sts_audio, ^wire, <<5, 0>>}, 1_000

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "before-onset", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert :sys.get_state(context.provider).wire == wire
      refute_received {:test_google_sts_started, _, _}
      refute_received {:vxpipe_sts_speech_started, ^capability, _, _}

      turn = begin_reply(context, :provider)
      complete_reply(context, turn, "AFTER GENUINE ONSET", 2)
      deliver(context, interaction_end("IDLE"))

      assert_receive {:test_google_sts_started, _, _}, 1_000
    end
  end

  for work <- [:audio, :thought, :transcription, :generation, :interruption] do
    test "new #{work} cannot reuse idle even before a subsequent response has an owner" do
      context = start_controller()
      turn = begin_reply(context, :provider)
      complete_reply(context, turn, "PREVIOUS", 1)
      deliver(context, interaction_end("IDLE"))

      message =
        case unquote(work) do
          :audio ->
            audio_message(2)

          :thought ->
            content(%{
              "modelTurn" => %{"parts" => [%{"text" => "private thought", "thought" => true}]}
            })

          :transcription ->
            content(%{"outputTranscription" => %{"text" => "new model work"}})

          :generation ->
            content(%{"generationComplete" => true})

          :interruption ->
            content(%{"interrupted" => true})
        end

      deliver(context, message)

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "during-model-work", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert :sys.get_state(context.provider).wire == context.wire
      refute_received {:test_google_sts_started, _, _}
      deliver(context, interaction_end("IDLE"))

      assert_receive {:test_google_sts_started, _, _}, 1_000
    end
  end

  for boundary <- ["generationComplete", "interrupted"] do
    test "#{boundary} in the same envelope cannot erase explicit idle completion" do
      context = start_controller()

      deliver(
        context,
        content(%{
          unquote(boundary) => true,
          "turnComplete" => true,
          "interactionStatus" => "IDLE"
        })
      )

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "same-envelope-idle", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, _, _}, 1_000
    end
  end

  for timing <- [:before_end, :after_end, :after_playback] do
    test "caller final #{timing} retains the exact caller and cannot trigger a reply" do
      context = start_controller()
      turn = start_caller(context)
      capability = context.capability

      deliver(context, content(%{"interimInputTranscription" => %{"text" => "provisional"}}))

      assert_receive {:vxpipe_sts_input_event, ^capability,
                      %{
                        event: %Event{
                          kind: :input_transcript,
                          turn_ref: ^turn,
                          text: "provisional",
                          final: false
                        }
                      }},
                     1_000

      if unquote(timing == :before_end), do: final_caller(context, turn, "caller final")
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
      deliver(context, activity("ACTIVITY_END"))
      assert_started(context, turn)

      if unquote(timing == :after_end), do: final_caller(context, turn, "caller final")
      complete_reply(context, turn, "REPLY", 1)
      if unquote(timing == :after_playback), do: final_caller(context, turn, "caller final")

      assert :sys.get_state(capability).caller_turns == %{}
      refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
      refute_received {:vxpipe_sts_speech_started, ^capability, _, _}
    end
  end

  test "twenty sequential late caller finals retire their bounded controller slots" do
    context = start_controller()

    for index <- 1..20 do
      turn = start_caller(context)
      deliver(context, activity("ACTIVITY_END"))
      assert_started(context, turn)
      complete_reply(context, turn, "REPLY #{index}", index)
      final_caller(context, turn, "CALLER #{index}")
      deliver(context, interaction_end("IDLE"))
      assert :sys.get_state(context.capability).caller_turns == %{}
    end
  end

  # Live Gemini calls (2026-10-07) ended when a caller turn produced no input transcription
  # and the next turn began: the session failed rather than guess the missing final's owner.
  # The call must continue. Without a correlation ID the late final cannot be attributed, so
  # the earlier turn and the next final are both settled without text; nothing is guessed.
  test "a competing caller onset settles the missing final without text and keeps the call" do
    context = start_controller()
    capability = context.capability
    first = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, first)
    complete_reply(context, first, "REPLY", 1)
    provider = context.provider
    monitor = Process.monitor(provider)

    second = start_caller(context)
    refute second == first
    assert_settled_without_text(capability, first)

    deliver(context, content(%{"inputTranscription" => %{"text" => "LATE OR SECOND"}}))
    assert_settled_without_text(capability, second)
    deliver(context, content(%{"inputTranscription" => %{"text" => "SECOND"}}))
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, second)
    complete_reply(context, second, "SECOND REPLY", 2)

    third = start_caller(context)
    final_caller(context, third, "THIRD")
    refute_received {:DOWN, ^monitor, :process, ^provider, _}
    assert :sys.get_state(context.provider).resumption_ambiguous?

    refute_received {:vxpipe_sts_input_event, _,
                     %{event: %Event{kind: :input_transcript, text: "LATE OR SECOND"}}}

    refute_received {:vxpipe_sts_input_event, _,
                     %{event: %Event{kind: :input_transcript, text: "SECOND"}}}
  end

  test "a typed submission cannot acquire an earlier audio caller's final" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    complete_reply(context, turn, "AUDIO REPLY", 1)
    assert :ok = SpeechToSpeech.push_text(context.capability, "typed input")
    final_caller(context, turn, "AUDIO CALLER")
    assert :sys.get_state(context.capability).caller_turns == %{}
  end

  test "model interruption cannot erase unfinished caller transcription evidence" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    deliver(context, content(%{"interrupted" => true}))
    final_caller(context, turn, "CALLER AFTER MODEL INTERRUPTION")
    assert :sys.get_state(context.capability).caller_turns == %{}
  end

  test "a final snapshot cannot be replaced before the caller's activity ends" do
    context = start_controller()
    turn = start_caller(context)
    final_caller(context, turn, "FIRST FINAL")
    deliver(context, content(%{"inputTranscription" => %{"text" => "DUPLICATE"}}))
    deliver(context, content(%{"interimInputTranscription" => %{"text" => "LATE INTERIM"}}))
    refute_received {:vxpipe_sts_input_event, _, %{event: %Event{kind: :input_transcript}}}
    refute_received {:vxpipe_sts_turn_started, _, _, _, _}
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    assert :sys.get_state(context.capability).caller_turns == %{}
  end

  test "unassociated input snapshots cannot create or prefill a caller" do
    context = start_controller()
    deliver(context, content(%{"inputTranscription" => %{"text" => "UNASSOCIATED"}}))
    deliver(context, content(%{"interimInputTranscription" => %{"text" => "UNASSOCIATED"}}))
    refute_received {:vxpipe_sts_input_event, _, _}
    refute_received {:vxpipe_sts_turn_started, _, _, _, _}
    turn = start_caller(context)
    final_caller(context, turn, "NEW CALLER")
    refute_received {:vxpipe_sts_input_event, _, %{event: %Event{kind: :input_transcript}}}
  end

  test "external competing onset settles the missing final and starts the next activity" do
    context = start_controller("external")
    assert :ok = SpeechToSpeech.input_activity(context.capability, :started)
    assert :ok = SpeechToSpeech.input_activity(context.capability, :ended)
    wire = context.wire
    assert_receive {:test_google_sts_control, ^wire, _start}
    assert_receive {:test_google_sts_control, ^wire, _end}
    provider = context.provider
    monitor = Process.monitor(provider)
    assert :ok = SpeechToSpeech.input_activity(context.capability, :started)
    assert_receive {:test_google_sts_control, ^wire, _next_start}, 1_000

    assert_receive {:vxpipe_sts_input_event, _,
                    %{event: %Event{kind: :input_transcript, text: "", final: true}}},
                   1_000

    refute_received {:DOWN, ^monitor, :process, ^provider, _}
  end

  test "pending caller final prevents socket replacement after model end and playback" do
    context = start_controller()
    turn = start_caller(context)
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    complete_reply(context, turn, "REPLY", 1)
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "before-final", "resumable" => true}
    })

    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    final_caller(context, turn, "LATE CALLER")

    assert_receive {:test_google_sts_started, _, _}, 1_000
  end

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
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
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
    deliver(context, content(%{"interimInputTranscription" => %{"text" => "partial"}}))
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_input_event, ^capability, %{event: %Event{kind: :turn_ended}}}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
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
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
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
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "a settled reply cannot contribute text to the next reply" do
    context = start_controller()

    for {text, index} <- [{"FIRST", 1}, {"SECOND", 2}] do
      turn = start_caller(context)
      final_caller(context, turn, "CALLER #{index}")
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
    final_caller(context, turn, "CALLER")
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
    deliver(context, interaction_end("IDLE"))

    assert_receive {:test_google_sts_started, pending, _}, 1_000
    assert_receive {:test_google_sts_control, ^pending, setup}, 1_000
    assert JSON.decode!(setup)["setup"]["sessionResumption"] == %{"handle" => "before-model-end"}
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
    refute_received {:vxpipe_sts_agent_transcript, _, _, _, _, _, _, _}
  end

  test "external idle end sends no wire boundary or output admission" do
    context = start_controller("external")
    assert :ok = SpeechToSpeech.input_activity(context.capability, :ended)
    _ = :sys.get_state(context.capability)
    refute_received {:test_google_sts_control, _, _}
    refute_received {:vxpipe_sts_turn_started, _, _, _, _}
  end

  test "external duplicates admit and send each boundary once without provider control" do
    context = start_controller("external")
    wire = context.wire
    capability = context.capability
    deliver(context, activity("ACTIVITY_START"))
    deliver(context, activity("ACTIVITY_END"))
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_turn_started, _, _, _, _}
    refute_received {:vxpipe_sts_speech_started, _, _, _}

    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    assert_receive {:test_google_sts_control, ^wire, started}
    assert JSON.decode!(started) == %{"realtimeInput" => %{"activityStart" => %{}}}
    refute_received {:test_google_sts_control, ^wire, _}

    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:test_google_sts_control, ^wire, ended}
    assert JSON.decode!(ended) == %{"realtimeInput" => %{"activityEnd" => %{}}}
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn, _}
    _ = :sys.get_state(capability)
    refute_received {:test_google_sts_control, ^wire, _}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    assert :sys.get_state(capability).pending_turns == []
    complete_reply(context, turn, "EXTERNAL", 1)
  end

  test "admitted interrupted text cannot leak into a fresh reply" do
    context = start_controller()
    old_turn = start_caller(context)
    final_caller(context, old_turn, "OLD CALLER")
    deliver(context, content(%{"outputTranscription" => %{"text" => "OLD"}}))
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, old_turn)
    deliver(context, audio_message(1))
    assert_audio(context, 1)
    deliver(context, content(%{"interrupted" => true}))
    deliver(context, content(%{"outputTranscription" => %{"text" => "LATE"}}))
    deliver(context, interaction_end("IDLE"))
    turn = start_caller(context)
    assert turn != old_turn
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, turn)
    deliver(context, content(%{"outputTranscription" => %{"text" => "NEW"}}))
    deliver(context, audio_message(2))
    assert_audio(context, 2)
    finish_generation(context)
    finish_playback(context, turn, "NEW", 20)
    refute_received {:vxpipe_sts_turn_completed, _, _, ^old_turn, _}
  end

  test "pre-admission model interruption cannot fabricate caller completion" do
    context = start_controller()
    old_turn = start_caller(context)
    capability = context.capability
    deliver(context, content(%{"outputTranscription" => %{"text" => "OLD"}}))
    deliver(context, content(%{"interrupted" => true}))
    deliver(context, interaction_end("IDLE"))
    refute_received {:vxpipe_sts_input_event, ^capability, %{event: %Event{kind: :turn_ended}}}
    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}
    final_caller(context, old_turn, "CALLER")
    deliver(context, activity("ACTIVITY_END"))
    assert_started(context, old_turn)
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
    assert :sys.get_state(capability).caller_turns == %{}
    complete_reply(context, old_turn, "FRESH REPLY AFTER CALLER END", 1)
  end

  test "renewal allows an existing external caller to finish after model interruption" do
    context = start_controller("external")
    capability = context.capability
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    deliver(context, content(%{"interrupted" => true}))
    deliver(context, interaction_end("IDLE"))
    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn, _}, 1_000
    final_caller(context, turn, "EXTERNAL CALLER")
    complete_reply(context, turn, "FRESH REPLY", 1)

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "old-model-end", "resumable" => true}
    })

    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    deliver(context, interaction_end("IDLE"))

    assert_receive {:test_google_sts_started, _, _}, 1_000
  end

  test "delayed interrupted-model completion cannot authorize the preserved caller's renewal" do
    context = start_controller("external")
    capability = context.capability
    assert :ok = SpeechToSpeech.input_activity(capability, :started)
    deliver(context, content(%{"interrupted" => true}))
    deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
    assert :ok = SpeechToSpeech.input_activity(capability, :ended)
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn, _}, 1_000
    deliver(context, interaction_end("IDLE"))
    final_caller(context, turn, "EXTERNAL CALLER")
    complete_reply(context, turn, "FRESH REPLY", 1)

    deliver(context, %{
      "sessionResumptionUpdate" => %{
        "newHandle" => "ambiguous-interrupted-end",
        "resumable" => true
      }
    })

    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    deliver(context, interaction_end("IDLE"))

    deliver(context, %{
      "sessionResumptionUpdate" => %{"newHandle" => "later-still-ambiguous", "resumable" => true}
    })

    assert :sys.get_state(context.provider).wire == context.wire
    refute_received {:test_google_sts_started, _, _}
    provider = context.provider
    monitor = Process.monitor(provider)
    TestGoogleSTSTransport.disconnect(context.wire)
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :session_failed}}, 1_000
    refute_received {:test_google_sts_started, _, _}
  end

  for {mode, turn_control} <- [provider: "provider", typed: "provider", external: "external"] do
    test "#{mode} overlapping model lifetimes cannot create a false idle checkpoint" do
      mode = unquote(mode)
      context = start_controller(unquote(turn_control))
      first = begin_reply(context, mode)
      complete_reply(context, first, "FIRST", 1)
      second = begin_reply(context, mode)
      deliver(context, interaction_end("IDLE"))
      complete_reply(context, second, "SECOND", 2)

      deliver(context, %{
        "sessionResumptionUpdate" => %{"newHandle" => "ambiguous-model-end", "resumable" => true}
      })

      deliver(context, %{"goAway" => %{"timeLeft" => "60s"}})
      assert :sys.get_state(context.provider).wire == context.wire
      refute_received {:test_google_sts_started, _, _}
      deliver(context, interaction_end("IDLE"))

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

  defp submit_response_input(context, :provider) do
    assert :ok = SpeechToSpeech.push_audio(context.capability, "caller", <<1, 0>>)
    caller = start_caller(context)
    final_caller(context, caller, "CALLER")
    deliver(context, activity("ACTIVITY_END"))
    caller
  end

  defp submit_response_input(context, :external) do
    assert :ok = SpeechToSpeech.input_activity(context.capability, :started)
    %{caller: %{turn_ref: caller}} = :sys.get_state(context.provider)
    assert :ok = SpeechToSpeech.input_activity(context.capability, :ended)
    _ = :sys.get_state(context.capability)
    final_caller(context, caller, "EXTERNAL CALLER")
    caller
  end

  defp submit_response_input(context, :typed) do
    assert :ok = SpeechToSpeech.push_text(context.capability, "synthetic input")
    %{input_turn: caller} = :sys.get_state(context.provider)
    _ = :sys.get_state(context.capability)
    assert is_reference(caller)
    caller
  end

  defp begin_reply(context, :provider) do
    turn = start_caller(context)
    final_caller(context, turn, "CALLER")
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
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", turn, _}, 1_000
    if mode == :external, do: final_caller(context, turn, "EXTERNAL CALLER")
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

  defp caller_boundary(context, "external", boundary) do
    assert :ok = SpeechToSpeech.input_activity(context.capability, boundary)
  end

  defp caller_boundary(context, "provider", :started) do
    # Real PCM arrives before the provider's VAD onset.
    assert :ok = SpeechToSpeech.push_audio(context.capability, "caller", <<1, 0>>)
    deliver(context, activity("ACTIVITY_START"))
  end

  defp caller_boundary(context, "provider", :ended),
    do: deliver(context, activity("ACTIVITY_END"))

  defp final_caller(context, turn, text) do
    deliver(context, content(%{"inputTranscription" => %{"text" => text}}))
    capability = context.capability

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      event: %Event{
                        kind: :input_transcript,
                        turn_ref: ^turn,
                        text: ^text,
                        final: true
                      }
                    }},
                   1_000
  end

  defp assert_settled_without_text(capability, turn) do
    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      event: %Event{
                        kind: :input_transcript,
                        turn_ref: ^turn,
                        text: "",
                        final: true
                      }
                    }},
                   1_000
  end

  defp settle_audio_caller(context) do
    turn = start_caller(context)
    final_caller(context, turn, "CALLER")
    deliver(context, activity("ACTIVITY_END"))
  end

  defp assert_new_origin_busy(context, first_context) do
    capability = context.capability
    wire = context.wire
    assert :ok = SpeechToSpeech.release(capability, make_ref())
    assert {:error, :busy} = SpeechToSpeech.push_audio(capability, "caller", <<1, 0>>)
    _ = :sys.get_state(wire)
    refute_received {:test_google_sts_audio, ^wire, <<1, 0>>}
    assert :sys.get_state(context.provider).interaction_context == first_context
  end

  defp start_controller(turn_control \\ "provider", provider_options \\ []) do
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
         provider: {STSSession, Keyword.merge([turn_control: turn_control], provider_options)},
         provider_private: private,
         sink: sink,
         frame_identity: %{}}
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:test_google_sts_started, wire, _}, 1_000
    assert_receive {:test_google_sts_control, ^wire, _setup}, 1_000
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
    assert_receive {:vxpipe_sts_turn_started, ^capability, "agent", ^turn, _}, 1_000
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
    assert frame.sample_rate == 48_000
    assert frame.payload == :binary.copy(<<index::little-signed-16>>, 960)
    assert div(byte_size(frame.payload) * 1_000, frame.sample_rate * 2) == 20
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
                    ^duration, _, _},
                   1_000

    assert_receive {:vxpipe_sts_turn_completed, ^capability, "agent", ^turn, _}, 1_000
    refute_received {:vxpipe_sts_agent_transcript, ^capability, _, _, _, _, _, _}
  end

  defp activity(type), do: %{"voiceActivity" => %{"type" => type}}
  defp content(body), do: %{"serverContent" => body}

  defp interaction_end(:missing), do: content(%{"turnComplete" => true})

  defp interaction_end(status),
    do: content(%{"turnComplete" => true, "interactionStatus" => status})

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
