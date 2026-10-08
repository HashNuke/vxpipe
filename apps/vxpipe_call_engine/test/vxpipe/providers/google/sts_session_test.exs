defmodule Vxpipe.Providers.Google.STSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Google.{STS, STSSession}
  alias Vxpipe.CallEngine.TestGoogleSTSTransport

  for response_start <- [false, true] do
    @opening_response_start response_start
    test "generated opening with response-start #{@opening_response_start} produces agent audio without a caller turn" do
      response_start? =
        Keyword.fetch!([response_start?: @opening_response_start], :response_start?)

      {session, wire} = start_session(response_start?: response_start?)
      assert_receive {:test_google_sts_control, ^wire, setup}
      assert Map.has_key?(JSON.decode!(setup), "setup")
      context = make_ref()
      options = if response_start?, do: [response_context: context], else: []
      assert :ok = Session.begin_opening(session, :generated, options)
      assert_receive {:test_google_sts_control, ^wire, control}
      cue = JSON.decode!(control)["realtimeInput"]["text"]
      assert is_binary(cue) and cue =~ "Begin the conversation"

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)

      legacy_output =
        if not response_start? do
          assert_receive {:vxpipe_speech,
                          %Event{session: ^session, kind: :opening_started} = opening}

          assert :ok = Session.ack(session, opening)
          assert {:ok, output} = Session.admit_output(session, opening.turn_ref)
          output
        end

      pcm = :binary.copy(<<1, 0>>, 480)

      deliver(wire, %{
        "serverContent" => %{
          "inputTranscription" => %{"text" => cue},
          "outputTranscription" => %{"text" => "HELLO"},
          "modelTurn" => %{
            "parts" => [
              %{
                "inlineData" => %{
                  "mimeType" => "audio/pcm;rate=24000",
                  "data" => Base.encode64(pcm)
                }
              }
            ]
          },
          "generationComplete" => true
        }
      })

      output =
        if response_start? do
          assert_receive {:vxpipe_speech,
                          %Event{
                            session: ^session,
                            kind: :response_started,
                            response_context: ^context
                          } = started}

          assert :ok = Session.ack(session, started)
          assert {:ok, output} = Session.admit_output(session, started.turn_ref)
          output
        else
          legacy_output
        end

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_transcript, text: "HELLO"} = text}

      assert :ok = Session.ack(session, text)
      assert_receive {:vxpipe_speech_audio, %Audio{session: ^session, payload: ^pcm} = audio}
      assert :ok = Session.ack_audio(session, audio)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_completed} = completed}

      assert :ok = Session.ack(session, completed)
      assert :ok = Session.settle_output(session, output, 20)
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript}}
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}
      assert :sys.get_state(Session.provider(session)).caller == nil
    end
  end

  for response_start <- [false, true] do
    @fixed_response_start response_start
    test "fixed opening with response-start #{@fixed_response_start} holds output until the complete exact transcript" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)
      {session, wire} = start_session(response_start?: profile)
      context = make_ref()
      options = if profile, do: [response_context: context], else: []
      assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)
      output = opening_output(session, profile)
      for index <- 1..100, do: deliver_sync(session, wire, audio_message(index))

      deliver_sync(session, wire, %{
        "serverContent" => %{"outputTranscription" => %{"text" => "GOOD "}}
      })

      refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript}}
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :response_started}}

      deliver(wire, %{
        "serverContent" => %{
          "outputTranscription" => %{"text" => "DAY"},
          "generationComplete" => true
        }
      })

      output = if profile, do: response_output(session, context), else: output

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_transcript, text: "GOOD DAY"} = text}

      assert :ok = Session.ack(session, text)
      assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}

      assert audio.payload ==
               IO.iodata_to_binary(for index <- 1..100, do: <<index::little-signed-16>>)

      assert :ok = Session.ack_audio(session, audio)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_completed} = completed}

      assert :ok = Session.ack(session, completed)
      assert :ok = Session.settle_output(session, output, 0)
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript}}
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}
    end

    # Live Gemini (2026-10-07) can signal generation completion before the opening's output
    # transcription arrives; verifying at that moment failed the session, so the call never
    # heard its opening. The transcript is awaited until the turn completes.
    test "fixed opening with response-start #{@fixed_response_start} verifies a transcript that follows generation completion" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)
      {session, wire} = start_session(response_start?: profile)
      context = make_ref()
      options = if profile, do: [response_context: context], else: []
      assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)
      output = opening_output(session, profile)
      deliver_sync(session, wire, audio_message(1))
      deliver_sync(session, wire, %{"serverContent" => %{"generationComplete" => true}})
      refute_received {:vxpipe_speech_closed, ^session, _}
      refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}

      deliver(wire, %{"serverContent" => %{"outputTranscription" => %{"text" => "GOOD DAY"}}})
      output = if profile, do: response_output(session, context), else: output

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_transcript, text: "GOOD DAY"} = text}

      assert :ok = Session.ack(session, text)
      assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
      assert :ok = Session.ack_audio(session, audio)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_completed} = completed}

      assert :ok = Session.ack(session, completed)
      assert :ok = Session.settle_output(session, output, 0)
      deliver(wire, %{"serverContent" => %{"turnComplete" => true}})
      refute_receive {:vxpipe_speech_closed, ^session, _}, 100
    end

    # Live Gemini transcribed the fixed opening "Alpha." as "Alpha" (2026-10-07). Speech
    # transcription does not carry the author's punctuation or case; the words must match.
    test "fixed opening with response-start #{@fixed_response_start} verifies the words, not punctuation" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)
      {session, wire} = start_session(response_start?: profile)
      context = make_ref()
      options = if profile, do: [response_context: context], else: []
      assert :ok = Session.begin_opening(session, {:fixed, "Good day, caller."}, options)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)
      _output = opening_output(session, profile)
      deliver_sync(session, wire, audio_message(1))

      deliver(wire, %{
        "serverContent" => %{
          "outputTranscription" => %{"text" => "good day caller"},
          "generationComplete" => true
        }
      })

      if profile, do: response_output(session, context)

      assert_receive {:vxpipe_speech,
                      %Event{
                        session: ^session,
                        kind: :output_transcript,
                        text: "Good day, caller."
                      }}

      refute_received {:vxpipe_speech_closed, ^session, _}
    end

    test "opening with response-start #{@fixed_response_start} cannot replace an unsettled opening" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)
      {session, wire} = start_session(response_start?: profile)
      assert_receive {:test_google_sts_control, ^wire, _setup}
      options = if profile, do: [response_context: make_ref()], else: []
      assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)
      assert_receive {:test_google_sts_control, ^wire, _cue}

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)
      _output = opening_output(session, profile)
      assert {:error, :busy} = Session.begin_opening(session, :generated, options)
      refute_received {:test_google_sts_control, ^wire, _replacement}
    end

    test "fixed opening with response-start #{@fixed_response_start} drops interrupted or overflowing unverified output" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)

      for failure <- [:interrupted, :caller_started, :overflow] do
        {session, wire} = start_session(response_start?: profile)
        options = if profile, do: [response_context: make_ref()], else: []
        assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

        assert_receive {:vxpipe_speech,
                        %Event{session: ^session, kind: :input_submitted} = submitted}

        assert :ok = Session.ack(session, submitted)
        _output = opening_output(session, profile)
        deliver_sync(session, wire, audio_message(1))

        case failure do
          :interrupted ->
            deliver(wire, %{"serverContent" => %{"interrupted" => true}})

          :caller_started ->
            deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})

          :overflow ->
            for _index <- 1..15, do: deliver_sync(session, wire, opening_large_audio())
            deliver(wire, opening_large_audio())
        end

        assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
        refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
        refute_received {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript}}
      end
    end

    test "fixed opening with response-start #{@fixed_response_start} releases completed audio without fabricating missing text" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)
      {session, wire} = start_session(response_start?: profile)
      context = make_ref()
      options = if profile, do: [response_context: context], else: []
      assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :input_submitted} = submitted}

      assert :ok = Session.ack(session, submitted)
      output = opening_output(session, profile)
      deliver_sync(session, wire, audio_message(1))
      deliver_sync(session, wire, %{"serverContent" => %{"generationComplete" => true}})
      refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
      deliver(wire, %{"serverContent" => %{"turnComplete" => true}})
      output = if profile, do: response_output(session, context), else: output

      assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
      assert audio.payload == <<1::little-signed-16>>
      assert :ok = Session.ack_audio(session, audio)

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :output_completed} = completed}

      assert :ok = Session.ack(session, completed)
      assert :ok = Session.settle_output(session, output, 0)
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript}}
      refute_received {:vxpipe_speech_closed, ^session, _}
      assert :ok = Session.push_text(session, "Continue", options)
    end

    test "fixed opening with response-start #{@fixed_response_start} rejects different or incomplete transcripts without releasing audio" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)

      for transcript <- ["RECEIVED GOOD DAY", "GOOD DAY EXTRA", "GOOD"] do
        {session, wire} = start_session(response_start?: profile)
        options = if profile, do: [response_context: make_ref()], else: []
        assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

        assert_receive {:vxpipe_speech,
                        %Event{session: ^session, kind: :input_submitted} = submitted}

        assert :ok = Session.ack(session, submitted)
        _output = opening_output(session, profile)
        deliver_sync(session, wire, audio_message(1))

        content = %{"outputTranscription" => %{"text" => transcript}}
        deliver(wire, %{"serverContent" => Map.put(content, "generationComplete", true)})
        deliver(wire, %{"serverContent" => %{"turnComplete" => true}})
        assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
        refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
        refute_received {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript}}
      end
    end

    test "fixed opening with response-start #{@fixed_response_start} rejects absent or unfinished audio" do
      profile = Keyword.fetch!([response_start?: @fixed_response_start], :response_start?)

      for audio <- [:absent, :unfinished] do
        {session, wire} = start_session(response_start?: profile)
        options = if profile, do: [response_context: make_ref()], else: []
        assert :ok = Session.begin_opening(session, {:fixed, "GOOD DAY"}, options)

        assert_receive {:vxpipe_speech,
                        %Event{session: ^session, kind: :input_submitted} = submitted}

        assert :ok = Session.ack(session, submitted)
        _output = opening_output(session, profile)

        case audio do
          :absent ->
            deliver(wire, %{"serverContent" => %{"generationComplete" => true}})

          :unfinished ->
            deliver_sync(session, wire, audio_message(1))
            deliver(wire, %{"serverContent" => %{"turnComplete" => true}})
        end

        assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
        refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
        refute_received {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript}}
      end
    end
  end

  test "audio backlog failure reports its bounded cause without PCM" do
    {session, wire} = start_session(response_start?: true)
    provider = Session.provider(session)
    handler = {:google_audio_failure, make_ref()}
    observer = self()

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :providers, :google, :sts, :failure],
        fn _event, _measurements, metadata, _config ->
          if self() == provider, do: send(observer, {:google_audio_failure, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert :ok = Session.push_text(session, "Reply", response_context: make_ref())

    for _index <- 1..17 do
      deliver(wire, %{
        "serverContent" => %{
          "modelTurn" => %{
            "parts" => [
              %{
                "inlineData" => %{
                  "mimeType" => "audio/pcm;rate=24000",
                  "data" => Base.encode64(:binary.copy(<<1, 0>>, 65_536))
                }
              }
            ]
          }
        }
      })
    end

    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:google_audio_failure, %{stage: :audio, reason: :audio_overflow}}
  end

  test "fixed-opening failure reports a bounded protocol reason without private content" do
    {session, wire} = start_session(response_start?: true)
    provider = Session.provider(session)
    handler = {:google_failure, make_ref()}
    observer = self()

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :providers, :google, :sts, :failure],
        fn _event, measurements, metadata, _config ->
          if self() == provider, do: send(observer, {:google_failure, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert :ok = Session.begin_opening(session, {:fixed, "NOTICE"}, response_context: make_ref())

    deliver(wire, %{
      "serverContent" => %{"outputTranscription" => %{"text" => "WRONG LONG NOTICE"}}
    })

    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000

    assert_receive {:google_failure, %{count: 1},
                    %{stage: :fixed_opening, reason: :text_mismatch}}

    refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
  end

  defp opening_large_audio do
    %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<1, 0>>, 65_536))
              }
            }
          ]
        }
      }
    }
  end

  defp opening_output(_session, true), do: nil

  defp opening_output(session, false) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :opening_started} = opening}
    assert :ok = Session.ack(session, opening)
    assert {:ok, output} = Session.admit_output(session, opening.turn_ref)
    output
  end

  defp response_output(session, context) do
    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :response_started, response_context: ^context} =
                      started}

    assert :ok = Session.ack(session, started)
    assert {:ok, output} = Session.admit_output(session, started.turn_ref)
    output
  end

  test "local response-start opt-in is a closed boolean descriptor choice" do
    assert {:ok, %{response_start?: false}} = STSSession.configure([])
    assert {:ok, %{response_start?: true}} = STSSession.configure(response_start?: true)

    for options <- [
          [response_start?: "true"],
          [response_start?: true, response_start?: false],
          [response_start?: true, unknown: true]
        ] do
      assert {:error, :invalid_configuration} = STSSession.configure(options)
    end
  end

  test "locally opted-in Google audio binds one accepted origin across IN_PROGRESS and blocks another" do
    {session, wire} = start_session(response_start?: true)
    first = make_ref()
    second = make_ref()
    pcm = <<1, 0>>

    assert :ok = Session.push_audio(session, pcm, response_context: first)
    assert_receive {:test_google_sts_audio, ^wire, ^pcm}
    provider = Session.provider(session)
    assert :sys.get_state(provider).interaction_context == first

    deliver_sync(session, wire, %{
      "serverContent" => %{"turnComplete" => true, "interactionStatus" => "IN_PROGRESS"}
    })

    assert :ok = Session.push_audio(session, pcm, response_context: first)
    assert_receive {:test_google_sts_audio, ^wire, ^pcm}
    assert {:error, :busy} = Session.push_audio(session, pcm, response_context: second)
    refute_received {:test_google_sts_audio, ^wire, _}
    assert :sys.get_state(provider).interaction_context == first
  end

  test "locally opted-in typed and external input carry context in the ordered callback" do
    context = make_ref()
    {typed, typed_wire} = start_session(response_start?: true)
    assert :ok = Session.push_text(typed, "hello", response_context: context)
    assert_receive {:test_google_sts_control, ^typed_wire, _text_control}
    assert_receive {:vxpipe_speech, %Event{session: ^typed, kind: :input_submitted} = submitted}
    assert :ok = Session.ack(typed, submitted)
    assert :sys.get_state(Session.provider(typed)).interaction_context == context

    {external, external_wire} = start_session(response_start?: true, turn_control: "external")
    assert :ok = Session.input_activity(external, :started, response_context: context)
    assert_receive {:test_google_sts_control, ^external_wire, _start_control}
    assert :ok = Session.input_activity(external, :ended, response_context: context)
    assert_receive {:test_google_sts_control, ^external_wire, _end_control}
    assert :sys.get_state(Session.provider(external)).interaction_context == context
  end

  test "provider-rejected first use does not bind a Google interaction origin" do
    {session, _wire} = start_session(response_start?: true)
    rejected = make_ref()
    # Exercise the provider's rollback rather than the channel's input validation.
    assert {:error, :session_failed} =
             STSSession.submit_input(Session.provider(session), rejected, {:audio, <<1>>})

    assert :sys.get_state(Session.provider(session)).interaction_context == nil
    refute_received {:test_google_sts_audio, _, _rejected_audio}
  end

  test "opted-in Google tool calls carry the bound interaction origin" do
    {session, wire} = start_session(response_start?: true)
    context = make_ref()
    pcm = <<1, 0>>
    assert :ok = Session.push_audio(session, pcm, response_context: context)
    assert_receive {:test_google_sts_audio, ^wire, ^pcm}

    deliver(wire, %{
      "toolCall" => %{
        "functionCalls" => [%{"id" => "origin-call", "name" => "echo", "args" => %{}}]
      }
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :tool_call, response_context: ^context} = call}

    assert :ok = Session.ack(session, call)
  end

  test "opted-in Google input cannot bypass context through legacy provider callbacks" do
    {session, wire} = start_session(response_start?: true, turn_control: "external")
    assert_receive {:test_google_sts_control, ^wire, _setup}
    provider = Session.provider(session)

    assert {:error, :unsupported_operation} = STSSession.push_audio(provider, <<1, 0>>)
    assert {:error, :unsupported_operation} = STSSession.push_text(provider, make_ref(), "text")
    assert {:error, :unsupported_operation} = STSSession.input_activity(provider, :started)
    refute_received {:test_google_sts_audio, ^wire, _}
    refute_received {:test_google_sts_control, ^wire, _}
    assert :sys.get_state(provider).interaction_context == nil
  end

  test "tampered private hybrid control fails before connecting a socket" do
    scope = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = STS.new(api_key: "synthetic")
    config = %{config | turn_control: "hybrid"}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: STSSession,
               options: [],
               owner: self(),
               private: [
                 config: config,
                 wire_module: TestGoogleSTSTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:vxpipe_speech_closed, ^session, :initialization_failed}, 1_000
    refute_received {:test_google_sts_started, _, _}
    refute_received {:test_google_sts_control, _, _}
  end

  test "a tampered trailing-newline tool name fails before socket connection" do
    scope = start_supervised!({CapabilityTree, owner: self()})

    tool = %{
      "name" => "lookup",
      "description" => "synthetic",
      "parametersJsonSchema" => %{"type" => "object"}
    }

    assert {:ok, config} = STS.new(api_key: "synthetic", tools: [tool])
    config = %{config | tools: [Map.put(tool, "name", "lookup\n")]}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: STSSession,
               options: [],
               owner: self(),
               private: [
                 config: config,
                 wire_module: TestGoogleSTSTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:vxpipe_speech_closed, ^session, :initialization_failed}, 1_000
    refute_received {:test_google_sts_started, _, _}
    refute_received {:test_google_sts_control, _, _}
  end

  test "tampered private setup fails before connecting a socket" do
    scope = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = STS.new(api_key: "synthetic")
    config = %{config | tools: [%{"private-invalid-schema" => "not a declaration"}]}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: STSSession,
               options: [],
               owner: self(),
               private: [
                 config: config,
                 wire_module: TestGoogleSTSTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:vxpipe_speech_closed, ^session, :initialization_failed}, 1_000
    refute_received {:test_google_sts_started, _, _}
  end

  test "private activation prompt and exact authorized declarations survive handle resumption" do
    alias Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation
    alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
    alias Vxpipe.CallEngine.TestAgentTool

    participant = %{
      prompt: "private-instruction-marker",
      variable_permissions: %{grants: %{}},
      tools: %{
        "test_agent_tool" => %ToolBinding{
          name: "test_agent_tool",
          type: :host,
          conversation_mode: :blocking,
          action: TestAgentTool
        }
      }
    }

    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, participant, [])
    definition = TestAgentTool.definition()

    expected = [
      %{
        "functionDeclarations" => [
          %{
            "name" => definition.name,
            "description" => definition.description,
            "parametersJsonSchema" => definition.parameters
          }
        ]
      }
    ]

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {session, wire} = start_session(activation: activation)
        assert_receive {:test_google_sts_control, ^wire, initial}
        initial = JSON.decode!(initial)["setup"]
        assert initial["systemInstruction"] == %{"parts" => [%{"text" => participant.prompt}]}
        assert initial["tools"] == expected
        refute JSON.encode!(initial) =~ "synthetic-google-sts-key"

        update_handle(session, wire, "private-resumption-marker")
        deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
        assert_receive {:test_google_sts_started, pending, _connection}
        assert_receive {:test_google_sts_control, ^pending, resumed}
        resumed = JSON.decode!(resumed)["setup"]

        assert resumed ==
                 Map.put(initial, "sessionResumption", %{"handle" => "private-resumption-marker"})

        deliver_sync(session, pending, %{"setupComplete" => %{}})
        refute_received {:test_google_sts_audio, ^pending, _}
        refute_received {:test_google_sts_control, ^pending, _}

        provider = Session.provider(session)

        for visible <- [session, :sys.get_status(provider)] do
          refute inspect(visible) =~ participant.prompt
          refute inspect(visible) =~ definition.description
          refute inspect(visible) =~ "private-resumption-marker"
          refute inspect(visible) =~ "synthetic-google-sts-key"
        end

        monitor = Process.monitor(provider)
        deliver(pending, %{"error" => %{"message" => participant.prompt}})
        assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
      end)

    refute log =~ participant.prompt
    refute log =~ definition.description
    refute log =~ "private-resumption-marker"
    refute log =~ "synthetic-google-sts-key"
  end

  test "active output overflow retires the allocation while consumer audio credit is held" do
    {session, wire, _output} = start_output()
    provider = Session.provider(session)
    provider_monitor = Process.monitor(provider)
    tree = Session.tree(session)
    tree_monitor = Process.monitor(tree)
    wire_monitor = Process.monitor(wire)

    deliver_sync(session, wire, audio_message(1))
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = held}
    assert held.payload == <<1, 0>>

    for index <- 2..17, do: deliver_sync(session, wire, audio_message(index))
    refute_received {:vxpipe_speech_audio, _}
    deliver(wire, audio_message(18))

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, {:shutdown, :session_failed}},
                   1_000

    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 1_000
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _reason}, 1_000
    refute_received {:test_google_sts_started, _, _}
    refute_received {:vxpipe_speech_audio, _}
  end

  test "acknowledged audio frees pending capacity and preserves FIFO through completion" do
    {session, wire, output} = start_output()
    deliver_sync(session, wire, audio_message(1))
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = first}
    for index <- 2..17, do: deliver_sync(session, wire, audio_message(index))

    assert :ok = Session.ack_audio(session, first)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = second}
    assert second.payload == <<2, 0>>
    deliver_sync(session, wire, audio_message(18))
    assert :ok = Session.ack_audio(session, second)

    for index <- 3..18 do
      assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
      assert audio.payload == <<index::little-signed-16>>
      assert :ok = Session.ack_audio(session, audio)
    end

    deliver(wire, %{"serverContent" => %{"generationComplete" => true}})

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed} = completed}

    assert :ok = Session.ack(session, completed)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "setup pins the live model with voice and transcriptions, keeping credentials private" do
    {_session, wire} = start_session()
    assert_receive {:test_google_sts_control, ^wire, setup}
    decoded = JSON.decode!(setup)
    assert decoded["setup"]["model"] == "models/gemini-3.8-live"
    assert decoded["setup"]["inputAudioTranscription"] == %{}
    assert decoded["setup"]["outputAudioTranscription"] == %{}
    assert get_in(decoded, ["setup", "generationConfig", "responseModalities"]) == ["AUDIO"]
    refute setup =~ "synthetic-google-sts-key"
  end

  test "input audio converts to 16k PCM and rejects malformed chunks" do
    {session, wire} = start_session()
    assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 160))
    assert_receive {:test_google_sts_audio, ^wire, _audio}
    assert {:error, :invalid_audio_size} = Session.push_audio(session, <<>>)
  end

  test "out-of-order transcripts and audio correlate to one turn with generation settlement" do
    {session, wire} = start_session()

    deliver(wire, %{"serverContent" => %{"outputTranscription" => %{"text" => "early text"}}})

    deliver(wire, %{
      "voiceActivity" => %{"type" => "ACTIVITY_START"},
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<4, 0>>, 200))
              }
            }
          ]
        }
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{
      "voiceActivity" => %{"type" => "ACTIVITY_END"},
      "serverContent" => %{"inputTranscription" => %{"text" => "hello"}}
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: ""} = ended}

    assert :ok = Session.ack(session, ended)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    deliver(wire, %{"serverContent" => %{"generationComplete" => true}})

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = done}
    assert :ok = Session.ack(session, done)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "server interruption before first audio fences the turn without output" do
    {session, wire} = start_session()

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)
    refute_received {:vxpipe_speech_audio, _}
  end

  test "provider-mode manual interrupt fails rather than sending client activity end" do
    {session, wire} = start_session()
    assert_receive {:test_google_sts_control, ^wire, _setup}
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    provider = Session.provider(session)
    monitor = Process.monitor(provider)

    assert {:error, :session_failed} = STSSession.interrupt(provider, started.turn_ref)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    refute_received {:test_google_sts_control, ^wire, _}
  end

  test "external-mode manual interrupt does not misuse idle activity end" do
    {session, wire} = start_session(turn_control: "external")
    assert_receive {:test_google_sts_control, ^wire, _setup}
    assert :ok = Session.input_activity(session, :started)
    assert_receive {:test_google_sts_control, ^wire, started}
    assert JSON.decode!(started) == %{"realtimeInput" => %{"activityStart" => %{}}}
    assert :ok = Session.input_activity(session, :ended)
    assert_receive {:test_google_sts_control, ^wire, ended}
    assert JSON.decode!(ended) == %{"realtimeInput" => %{"activityEnd" => %{}}}
    provider = Session.provider(session)
    turn = :sys.get_state(provider).input_turn
    assert is_reference(turn)
    monitor = Process.monitor(provider)

    assert {:error, :session_failed} = STSSession.interrupt(provider, turn)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    refute_received {:test_google_sts_control, ^wire, _}
  end

  test "opted-in current-wire interrupt fails without sending activity control" do
    {session, wire} = start_session(response_start?: true)
    assert_receive {:test_google_sts_control, ^wire, _setup}
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}

    deliver(wire, %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<5, 0>>, 200))
              }
            }
          ]
        }
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :response_started} = response}
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    assert {:error, :session_failed} = STSSession.interrupt(provider, response.turn_ref)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    refute_received {:test_google_sts_control, ^wire, _}
  end

  test "server interruption waits for an outstanding audio credit before terminal settlement" do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
    caller_final(session, wire, "CALLER")
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    deliver(wire, %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<5, 0>>, 200))
              }
            }
          ]
        }
      }
    })

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, request_ref: reference} =
                      completed}

    assert reference == output.ref
    assert :ok = Session.ack(session, completed)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "opted-in server interruption terminalizes only its credited response" do
    {session, wire} = start_session(response_start?: true)
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}

    deliver(wire, %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<5, 0>>, 200))
              }
            }
          ]
        }
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :response_started} = started}
    assert :ok = Session.ack(session, started)
    assert {:ok, output} = Session.admit_output(session, started.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert interrupted.turn_ref == started.turn_ref
    assert :ok = Session.ack(session, interrupted)
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, request_ref: reference} =
                      completed}

    assert reference == output.ref
    assert :ok = Session.ack(session, completed)
    assert :ok = Session.settle_output(session, output, 0)
    provider = Session.provider(session)
    _ = :sys.get_state(provider)
    assert :sys.get_state(provider).responses.records == %{}
  end

  test "a late output grant after an interrupted caller cannot strand the shared slot" do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
    caller_final(session, wire, "CALLER")
    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)

    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    assert {:ok, _output} = Session.admit_output(session, ended.turn_ref)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
  end

  test "delayed interrupted A credit cannot drop or relabel B text and PCM" do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = a_start}
    assert :ok = Session.ack(session, a_start)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = a_end}
    assert :ok = Session.ack(session, a_end)
    caller_final(session, wire, "A CALLER")
    assert {:ok, a_output} = Session.admit_output(session, a_end.turn_ref)
    deliver(wire, audio_message(1))
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = a_audio}
    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)
    deliver(wire, %{"serverContent" => %{"turnComplete" => true, "interactionStatus" => "IDLE"}})

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = b_start}
    assert :ok = Session.ack(session, b_start)
    assert b_start.turn_ref != a_start.turn_ref
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = b_end}
    assert :ok = Session.ack(session, b_end)
    caller_final(session, wire, "B CALLER")
    deliver(wire, %{"serverContent" => %{"outputTranscription" => %{"text" => "B SPOKEN"}}})
    deliver(wire, audio_message(2))
    deliver(wire, %{"serverContent" => %{"generationComplete" => true}})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :output_transcript}}
    refute_received {:vxpipe_speech_audio, %Audio{payload: <<2, 0>>}}

    assert :ok = Session.validate_audio(session, a_audio)
    assert :ok = Session.ack_audio(session, a_audio)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = a_done}
    assert a_done.turn_ref == a_start.turn_ref
    assert :ok = Session.ack(session, a_done)
    assert :ok = Session.settle_output(session, a_output, 0)
    assert {:ok, b_output} = Session.admit_output(session, b_end.turn_ref)

    assert_receive {:vxpipe_speech,
                    %Event{
                      session: ^session,
                      kind: :output_transcript,
                      turn_ref: b_turn,
                      text: "B SPOKEN"
                    } = b_text}

    assert b_turn == b_start.turn_ref
    assert :ok = Session.ack(session, b_text)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session, payload: <<2, 0>>} = b_audio}
    assert :ok = Session.validate_audio(session, b_audio)
    assert :ok = Session.ack_audio(session, b_audio)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = b_done}
    assert b_done.turn_ref == b_start.turn_ref
    assert :ok = Session.ack(session, b_done)
    assert :ok = Session.settle_output(session, b_output, 0)
  end

  test "competing caller cannot borrow output before interrupted model completion" do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = a_start}
    assert :ok = Session.ack(session, a_start)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = a_end}
    assert :ok = Session.ack(session, a_end)
    caller_final(session, wire, "A CALLER")
    assert {:ok, _output} = Session.admit_output(session, a_end.turn_ref)
    deliver(wire, audio_message(1))
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session}}
    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = b_start}
    assert :ok = Session.ack(session, b_start)

    pre_output = :sys.get_state(Session.provider(session))
    assert pre_output.input_turn == b_start.turn_ref
    assert %{interrupted?: true, turn_ref: a_turn} = pre_output.output
    assert a_turn == a_start.turn_ref
    assert b_start.turn_ref != a_turn
    assert pre_output.audio_fenced?

    deliver_sync(session, wire, %{
      "serverContent" => %{"outputTranscription" => %{"text" => "AMBIGUOUS"}}
    })

    deliver_sync(session, wire, audio_message(2))
    deliver_sync(session, wire, %{"serverContent" => %{"generationComplete" => true}})

    deliver(wire, %{
      "serverContent" => %{"interimInputTranscription" => %{"text" => "B STILL SPEAKING"}}
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = barrier}
    assert :ok = Session.ack(session, barrier)

    provider_state = :sys.get_state(Session.provider(session))
    assert provider_state.output_text == nil
    assert provider_state.audio_buffer == []
    refute provider_state.generation_pending_done?
    refute_received {:vxpipe_speech, %Event{kind: :output_transcript}}
    refute_received {:vxpipe_speech_audio, %Audio{payload: <<2, 0>>}}
  end

  test "settling interrupted A cannot erase B transcript buffered before B grant" do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = a_start}
    assert :ok = Session.ack(session, a_start)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = a_end}
    assert :ok = Session.ack(session, a_end)
    caller_final(session, wire, "A CALLER")
    assert {:ok, a_output} = Session.admit_output(session, a_end.turn_ref)

    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = a_done}
    assert a_done.turn_ref == a_start.turn_ref
    assert :ok = Session.ack(session, a_done)
    deliver(wire, %{"serverContent" => %{"turnComplete" => true, "interactionStatus" => "IDLE"}})

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = b_start}
    assert :ok = Session.ack(session, b_start)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = b_end}
    assert :ok = Session.ack(session, b_end)
    caller_final(session, wire, "B CALLER")
    deliver(wire, %{"serverContent" => %{"outputTranscription" => %{"text" => "B SPOKEN"}}})
    deliver(wire, %{"serverContent" => %{"generationComplete" => true}})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :output_transcript}}

    assert :ok = Session.settle_output(session, a_output, 0)
    assert {:ok, b_output} = Session.admit_output(session, b_end.turn_ref)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, text: "B SPOKEN"} = b_text}

    assert b_text.turn_ref == b_start.turn_ref
    assert :ok = Session.ack(session, b_text)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = b_done}
    assert b_done.turn_ref == b_start.turn_ref
    assert :ok = Session.ack(session, b_done)
    assert :ok = Session.settle_output(session, b_output, 0)
  end

  test "external turn control ignores wire activity and uses explicit boundaries" do
    {session, wire} = start_session(turn_control: "external")

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}

    assert :ok = Session.input_activity(session, :started)
    deliver(wire, %{"serverContent" => %{"interimInputTranscription" => %{"text" => "partial"}}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = partial}
    refute partial.final
    assert :ok = Session.ack(session, partial)
    assert :ok = Session.input_activity(session, :ended)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: ""} = ended}

    assert :ok = Session.ack(session, ended)
  end

  test "tool calls map provider ids to bounded results and cancellations" do
    {session, wire} = start_session()

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{
      "toolCall" => %{
        "functionCalls" => [
          %{"id" => "provider-1", "name" => "echo", "args" => %{"text" => "hi"}}
        ]
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = call}
    assert :ok = Session.ack(session, call)
    assert call.tool_name == "echo"

    provider = Session.provider(session)
    assert :ok = STSSession.send_tool_result(provider, call.call_ref, %{"ok" => true})
    assert_receive {:test_google_sts_control, ^wire, response}, 5_000
    response = drain_until_tool_response(wire, response)
    assert response =~ "provider-1"

    assert {:error, :stale_request} = STSSession.send_tool_result(provider, make_ref(), %{})

    deliver(wire, %{"toolCallCancellation" => %{"ids" => ["provider-2"]}})
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :tool_cancelled}}
  end

  test "audio after server interruption is dropped before the next turn" do
    {session, wire} = start_session()

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = caller_end}
    assert :ok = Session.ack(session, caller_end)
    caller_final(session, wire, "FIRST CALLER")

    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)

    deliver(wire, %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<5, 0>>, 200))
              }
            }
          ]
        },
        "generationComplete" => true
      }
    })

    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = next}
    assert :ok = Session.ack(session, next)
    assert next.turn_ref != started.turn_ref

    deliver(wire, %{
      "voiceActivity" => %{"type" => "ACTIVITY_END"},
      "serverContent" => %{"inputTranscription" => %{"text" => "again"}}
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: ""} = ended}

    assert :ok = Session.ack(session, ended)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)
  end

  for response_start? <- [false, true] do
    @tag :gemini_longevity
    test "silent microphone PCM preserves a settled checkpoint with response-start #{response_start?}" do
      {session, wire} = start_session(response_start?: unquote(response_start?))
      context = make_ref()
      options = if unquote(response_start?), do: [response_context: context], else: []
      # Establish the authorized input context before accepting a checkpoint.
      silence = :binary.copy(<<0, 0>>, 320)
      assert :ok = Session.push_audio(session, silence, options)
      assert_receive {:test_google_sts_audio, ^wire, ^silence}
      update_handle(session, wire, "synthetic-silent-checkpoint")
      assert :ok = Session.push_audio(session, silence, options)
      assert_receive {:test_google_sts_audio, ^wire, ^silence}
      deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, pending, _connection}
      assert_receive {:test_google_sts_control, ^pending, setup}

      assert JSON.decode!(setup)["setup"]["sessionResumption"] ==
               %{"handle" => "synthetic-silent-checkpoint"}
    end

    @tag :gemini_longevity
    test "pending rotation keeps caller audio flowing with response-start #{response_start?}" do
      {session, wire} = start_session(response_start?: unquote(response_start?))
      context = make_ref()
      options = if unquote(response_start?), do: [response_context: context], else: []
      assert :ok = Session.push_audio(session, <<1, 0>>, options)
      assert_receive {:test_google_sts_audio, ^wire, <<1, 0>>}
      deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})

      for sample <- 2..5 do
        pcm = <<sample::little-signed-16>>
        assert :ok = Session.push_audio(session, pcm, options)
        assert_receive {:test_google_sts_audio, ^wire, ^pcm}
      end

      refute_received {:test_google_sts_started, _, _}
    end

    @tag :gemini_longevity
    test "the actual socket switch retains one unsent command with response-start #{response_start?}" do
      {session, wire} = start_session(response_start?: unquote(response_start?))
      update_handle(session, wire, "synthetic-longevity-handle")
      deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, pending, _connection}
      provider = Session.provider(session)

      command =
        if unquote(response_start?),
          do: {:submit_input, make_ref(), {:audio, <<17, 0>>}},
          else: {:push_audio, <<17, 0>>}

      request = :gen_server.send_request(provider, command)
      _ = :sys.get_state(provider)
      assert :timeout = :gen_server.wait_response(request, 0)
      # The ordered input slot normally prevents this, but a second direct
      # provider submission must never grow the switchover buffer.
      assert {:error, :busy} = GenServer.call(provider, command)
      refute_received {:test_google_sts_audio, ^wire, _}
      refute_received {:test_google_sts_audio, ^pending, _}

      deliver_sync(session, pending, %{"setupComplete" => %{}})
      assert {:reply, :ok} = :gen_server.wait_response(request, 1_000)
      assert_receive {:test_google_sts_audio, ^pending, <<17, 0>>}
      refute_received {:test_google_sts_audio, ^pending, _duplicate}
    end

    @tag :gemini_longevity
    test "closing during a socket switch discards held input with response-start #{response_start?}" do
      {session, wire} = start_session(response_start?: unquote(response_start?))
      update_handle(session, wire, "synthetic-closing-handle")
      deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
      assert_receive {:test_google_sts_started, pending, _connection}
      provider = Session.provider(session)
      monitor = session |> Session.tree() |> Process.monitor()
      pending_monitor = Process.monitor(pending)

      command =
        if unquote(response_start?),
          do: {:submit_input, make_ref(), {:audio, <<19, 0>>}},
          else: {:push_audio, <<19, 0>>}

      request = :gen_server.send_request(provider, command)
      _ = :sys.get_state(provider)
      assert :timeout = :gen_server.wait_response(request, 0)
      assert :ok = Session.close(session)
      assert_receive {:DOWN, ^monitor, :process, _, _}
      assert_receive {:DOWN, ^pending_monitor, :process, ^pending, _}
      assert {:error, {_reason, ^provider}} = :gen_server.wait_response(request, 1_000)
      refute_received {:test_google_sts_audio, ^pending, _}
      refute_received {:test_google_sts_audio, ^wire, _}
    end
  end

  for timer <- [:renew, :expire] do
    @tag :gemini_longevity
    test "a healthy connection ignores the obsolete #{timer} timer" do
      {session, wire} = start_session()
      update_handle(session, wire, "synthetic-healthy-handle")
      provider = Session.provider(session)
      send(provider, {unquote(timer), wire})
      _ = :sys.get_state(provider)
      assert :ok = Session.push_audio(session, <<21, 0>>)
      assert_receive {:test_google_sts_audio, ^wire, <<21, 0>>}
      refute_received {:test_google_sts_started, _, _}
    end
  end

  @tag :gemini_retirement
  test "replacement waits for old peer retirement and retains its one unsent frame" do
    {session, wire} = start_session(retire_ack?: false)
    update_handle(session, wire, "synthetic-retiring-handle")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_retire, ^wire}
    refute_received {:test_google_sts_started, _, _}
    provider = Session.provider(session)
    request = :gen_server.send_request(provider, {:push_audio, <<23, 0>>})
    _ = :sys.get_state(provider)
    assert :timeout = :gen_server.wait_response(request, 0)
    TestGoogleSTSTransport.acknowledge_retirement(wire)
    _ = :sys.get_state(wire)
    _ = :sys.get_state(provider)
    refute_received {:test_google_sts_started, _, _}
    TestGoogleSTSTransport.finish_retirement(wire)
    assert_receive {:test_google_sts_started, pending, _}
    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert {:reply, :ok} = :gen_server.wait_response(request, 1_000)
    assert_receive {:test_google_sts_audio, ^pending, <<23, 0>>}
    refute_received {:test_google_sts_audio, ^wire, _}
  end

  @tag :gemini_retirement
  test "unacknowledged retirement consumes the original reconnect budget" do
    {session, wire} = start_session(retire_ack?: false, resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-stuck-retirement")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_retire, ^wire}
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_received {:test_google_sts_started, _, _}
  end

  @tag :gemini_session_active
  test "a still-active rejection retries the same handle without replay or a new budget" do
    {session, wire} = start_session()
    update_handle(session, wire, "synthetic-active-session")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_started, first, _}
    provider = Session.provider(session)
    deadline = :sys.get_state(provider).resume_deadline
    request = :gen_server.send_request(provider, {:push_audio, <<29, 0>>})
    _ = :sys.get_state(provider)
    TestGoogleSTSTransport.reject_session_active(first)
    assert_receive {:test_google_sts_started, second, _}
    assert first != second
    assert_receive {:test_google_sts_control, ^second, setup}

    assert JSON.decode!(setup)["setup"]["sessionResumption"] ==
             %{"handle" => "synthetic-active-session"}

    assert :sys.get_state(provider).resume_deadline == deadline
    assert :timeout = :gen_server.wait_response(request, 0)
    refute_received {:test_google_sts_audio, ^first, _}
    deliver_sync(session, second, %{"setupComplete" => %{}})
    assert {:reply, :ok} = :gen_server.wait_response(request, 1_000)
    assert_receive {:test_google_sts_audio, ^second, <<29, 0>>}
    refute_received {:test_google_sts_audio, ^second, _}
  end

  test "go-away without a resumption handle fails closed instead of restarting silently" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    deliver(wire, %{"goAway" => %{"timeLeft" => "0.050s"}})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
  end

  test "renewal uses the latest handle and resumes the same allocation only after setup acknowledgement" do
    {session, wire} = start_session()
    old_monitor = Process.monitor(wire)
    handle = "synthetic-latest-handle"
    update_handle(session, wire, "synthetic-old-handle")
    update_handle(session, wire, handle)
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})

    assert_receive {:test_google_sts_started, pending, _connection}
    assert pending != wire
    assert_receive {:test_google_sts_control, ^pending, setup}
    assert get_in(JSON.decode!(setup), ["setup", "sessionResumption", "handle"]) == handle
    assert_receive {:DOWN, ^old_monitor, :process, ^wire, _reason}
    refute_received {:test_google_sts_audio, ^pending, _}

    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<2, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<2, 0>>}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :ready}}

    # Retired-socket events and timers cannot affect the adopted generation.
    provider = Session.provider(session)
    send(provider, {:vxpipe_sts_transport, wire, {:closed, :connection_lost}})
    send(provider, {:expire, wire})
    send(provider, {:vxpipe_sts_transport, wire, {:message, ~s({"error":{}})}})
    assert :ok = Session.push_audio(session, <<3, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<3, 0>>}
    refute inspect(:sys.get_status(provider)) =~ handle
  end

  test "a revoked handle cannot be used after connection loss" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-revoked-handle")
    deliver_sync(session, wire, %{"sessionResumptionUpdate" => %{"resumable" => false}})
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "connection loss at a resumable idle boundary preserves the allocation" do
    {session, wire} = start_session()
    update_handle(session, wire, "synthetic-idle-handle")
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<4, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<4, 0>>}
  end

  test "unresolved accepted input blocks connection-loss resumption despite a retained token" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-before-input")
    assert :ok = Session.push_audio(session, <<5, 0>>)
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "a replacement that never acknowledges setup expires without a fresh-session fallback" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-timeout-handle")
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_started, pending, _connection}
    pending_monitor = Process.monitor(pending)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert_receive {:DOWN, ^pending_monitor, :process, ^pending, _reason}, 1_000
    refute_received {:test_google_sts_started, _, _}
  end

  test "renewal waits for playback settlement and sends no historical input or generated speech" do
    {session, wire} = start_session()
    output = finish_generation(session, wire)
    update_handle(session, wire, "synthetic-after-generation")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
    refute_received {:test_google_sts_started, _, _}

    assert :ok = Session.settle_output(session, output, 20)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, setup}
    decoded = JSON.decode!(setup)
    assert Map.keys(decoded) == ["setup"]
    refute Map.has_key?(decoded, "clientContent")
    assert decoded["setup"]["sessionResumption"]["handle"] == "synthetic-after-generation"

    deliver_sync(session, pending, %{"setupComplete" => %{}})
    refute_received {:test_google_sts_control, ^pending, _}
    refute_received {:test_google_sts_audio, ^pending, _}
    refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}

    # Only genuinely new caller input goes onto the resumed connection.
    assert :ok = Session.push_audio(session, <<7, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<7, 0>>}
    refute_received {:test_google_sts_audio, ^pending, _}
  end

  test "replacement setup failure never opens a fresh session" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-rejected-handle")
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver(pending, %{"error" => %{"code" => 400}})
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "go-away allows playback to settle before the shorter reconnect budget begins" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    output = finish_generation(session, wire)
    update_handle(session, wire, "synthetic-pending-playback")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "1s"}})
    refute_receive {:DOWN, ^monitor, :process, _, _}, 100

    assert :ok = Session.settle_output(session, output, 20)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<8, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<8, 0>>}
    refute_received {:DOWN, ^monitor, :process, _, _}
  end

  test "Google STS is declared and accepts the configured Gemini selection" do
    assert {:ok, STSSession} = Vxpipe.Providers.Registry.fetch_capability("google", :sts)

    selection = %Vxpipe.CallEngine.CallSpec.CapabilitySelection{
      kind: :speech_to_speech,
      provider: "google",
      model: "gemini-3.8-live",
      credential_name: nil,
      options: %{},
      provider_options: %{}
    }

    assert :ok = Vxpipe.CallEngine.CapabilityCatalog.validate(selection)
  end

  defp start_session(opts \\ []) do
    turn_control = Keyword.get(opts, :turn_control, "provider")

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, base_config} =
      STS.new(
        api_key: "synthetic-google-sts-key",
        model: "gemini-3.8-live",
        voice: "Kore",
        turn_control: turn_control
      )

    config =
      case Keyword.fetch(opts, :activation) do
        {:ok, activation} ->
          {:ok, {STSSession, _public}, private} =
            Vxpipe.CallEngine.SpeechToSpeechRuntime.provider(
              {STSSession, [api_key: "synthetic-google-sts-key", turn_control: turn_control]},
              [],
              activation
            )

          Keyword.fetch!(private, :config)

        :error ->
          base_config
      end

    private =
      [
        config: config,
        wire_module: TestGoogleSTSTransport,
        wire_options: [observer: self(), retire_ack?: Keyword.get(opts, :retire_ack?, true)]
      ] ++ Keyword.take(opts, [:resumption_timeout_ms])

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope),
        provider: STSSession,
        options:
          [model: "gemini-3.8-live", voice: "Kore", turn_control: turn_control] ++
            Keyword.take(opts, [:response_start?]),
        private: private,
        owner: self()
      )

    assert_receive {:test_google_sts_started, wire, _connection}, 5_000
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(%{"setupComplete" => %{}}))

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    {session, wire}
  end

  defp start_output do
    {session, wire} = start_session()
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)
    {session, wire, output}
  end

  defp audio_message(index) do
    %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(<<index::little-signed-16>>)
              }
            }
          ]
        }
      }
    }
  end

  defp deliver(wire, message) do
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(message))
  end

  defp deliver_sync(session, wire, message) do
    deliver(wire, message)
    _ = :sys.get_state(wire)
    _ = :sys.get_state(Session.provider(session))
    :ok
  end

  defp update_handle(session, wire, handle) do
    deliver_sync(session, wire, %{
      "sessionResumptionUpdate" => %{"newHandle" => handle, "resumable" => true}
    })
  end

  defp finish_generation(session, wire) do
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    deliver(wire, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
    caller_final(session, wire, "CALLER BEFORE RENEWAL")
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    deliver(wire, %{
      "serverContent" => %{
        "outputTranscription" => %{"text" => "reply before reconnect"},
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<1, 0>>, 480))
              }
            }
          ]
        },
        "generationComplete" => true
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript} = text}
    assert :ok = Session.ack(session, text)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed} = completed}

    assert :ok = Session.ack(session, completed)

    deliver_sync(session, wire, %{
      "serverContent" => %{"turnComplete" => true, "interactionStatus" => "IDLE"}
    })

    output
  end

  defp caller_final(session, wire, text) do
    deliver(wire, %{"serverContent" => %{"inputTranscription" => %{"text" => text}}})

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :input_transcript, final: true} = event}

    assert :ok = Session.ack(session, event)
  end

  defp drain_until_tool_response(wire, response) do
    if response =~ "toolResponse" do
      response
    else
      assert_receive {:test_google_sts_control, ^wire, next}, 5_000
      drain_until_tool_response(wire, next)
    end
  end
end
