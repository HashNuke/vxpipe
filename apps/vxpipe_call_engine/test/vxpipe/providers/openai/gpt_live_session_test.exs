defmodule Vxpipe.Providers.OpenAI.GPTLiveSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestGPTLiveTransport
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  test "starts privately, waits for provider readiness and sends accepted audio in order" do
    scope = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             GPTLive.new(api_key: "synthetic-gpt-live-key", backend_model: "gpt-5.6")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: GPTLiveSession,
               options: [backend_model: "gpt-5.6"],
               private: [
                 config: config,
                 wire_module: TestGPTLiveTransport,
                 wire_options: [observer: self()]
               ],
               owner: self()
             )

    assert_receive {:test_gpt_live_started, wire, connection}
    assert connection.url == "wss://api.openai.com/v1/live/sessions"
    assert connection.headers == [{"authorization", "Bearer synthetic-gpt-live-key"}]
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"} = start}
    assert start["session"]["store"] == false
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :ready}}

    assert {:error, :not_ready} =
             Session.push_audio(session, <<1, 0>>, response_context: make_ref())

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.started",
      "session" => %{"id" => "session_1"}
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)

    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.append", "audio" => "AQA="}}
  end

  test "hold waits for the mute acknowledgment before adding context or completing" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)
    observer = self()

    start_supervised!(
      {Task,
       fn -> send(observer, {:hold_result, GPTLiveSession.set_input_hold(provider, true)}) end}
    )

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.mute", "event_id" => mute_id}}

    _ = :sys.get_state(provider)
    refute_received {:test_gpt_live_control, ^wire, %{"type" => "session.thinking.append"}}
    refute_received {:hold_result, _result}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_audio.muted",
      "client_event_id" => mute_id
    })

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.thinking.append"}}
    assert_receive {:hold_result, :ok}

    start_supervised!(
      Supervisor.child_spec(
        {Task,
         fn ->
           send(observer, {:release_result, GPTLiveSession.set_input_hold(provider, false)})
         end},
        id: make_ref()
      )
    )

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.unmute", "event_id" => unmute_id}}

    refute_received {:release_result, _result}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_audio.unmuted",
      "client_event_id" => unmute_id
    })

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.thinking.append"}}
    assert_receive {:release_result, :ok}
  end

  test "segments a continuous audio burst and aligns its spoken transcript" do
    {session, wire} = start_ready_session()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_transcript.delta",
      "delta" => "Hello",
      "start_ms" => 100,
      "end_ms" => 120
    })

    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :response_started, turn_ref: turn} = started},
                   1_000

    assert :ok = Session.ack(session, started)
    assert {:ok, output} = Session.admit_output(session, turn)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}, 1_000
    assert :binary.match(audio.payload, tone) != :nomatch
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, text: "Hello"} =
                      transcript},
                   1_000

    assert transcript.output_ref == output.ref
    assert :ok = Session.ack(session, transcript)

    silence = :binary.copy(<<0, 0>>, 480 * 40)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(silence)
    })
  end

  test "two delegated function calls wait for both results before continuing once" do
    {session, wire} = start_ready_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "Please check",
      "start_ms" => 0,
      "end_ms" => 100
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = onset}
    assert :ok = Session.ack(session, onset)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.delegation.created",
      "delegation" => %{"id" => "d1", "target" => "responses", "response_id" => "r1"}
    })

    for call_id <- ["a", "b"] do
      TestGPTLiveTransport.deliver(wire, %{
        "type" => "response.event",
        "delegation_id" => "d1",
        "event" => %{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "function_call",
            "status" => "completed",
            "call_id" => call_id,
            "name" => "echo",
            "arguments" => ~s({"value":"#{call_id}"})
          }
        }
      })
    end

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "response.event",
      "delegation_id" => "d1",
      "event" => %{"type" => "response.completed", "response" => %{"id" => "r1"}}
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = first}, 1_000
    assert :ok = Session.ack(session, first)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = second}, 1_000
    assert first.call_ref != second.call_ref
    assert first.response_context == context
    assert second.response_context == context
    assert :ok = Session.ack(session, second)

    provider = Session.provider(session)
    assert :ok = GPTLiveSession.send_tool_result(provider, first.call_ref, %{"ok" => "a"})
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.item.create"}}
    refute_received {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}

    assert :ok = GPTLiveSession.send_tool_result(provider, second.call_ref, %{"ok" => "b"})
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.item.create"}}
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}

    assert {:error, :stale_request} =
             GPTLiveSession.send_tool_result(provider, first.call_ref, %{})
  end

  test "caller fragments close at an inferred audio gap without a provider turn event" do
    {session, wire} = start_ready_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<0, 0>>, response_context: context)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "Hello",
      "start_ms" => 20,
      "end_ms" => 120
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = onset}
    assert :ok = Session.ack(session, onset)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = partial}
    assert partial.text == "Hello"
    assert partial.final == false
    assert :ok = Session.ack(session, partial)

    silence = :binary.copy(<<0, 0>>, div(24_000 * 800, 1_000))
    assert :ok = Session.push_audio(session, silence, response_context: context)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = final}
    assert final.text == "Hello"
    assert final.final == true
    assert :ok = Session.ack(session, final)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert ended.endpointing == :inferred_gap
    assert :ok = Session.ack(session, ended)
  end

  test "a complete burst buffered before room admission still plays and completes" do
    {session, wire} = start_ready_session()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    tone = :binary.copy(<<0, 16>>, 480)
    silence = :binary.copy(<<0, 0>>, 480 * 40)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone <> silence)
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :response_started, turn_ref: turn} = started},
                   1_000

    assert :ok = Session.ack(session, started)
    assert {:ok, output} = Session.admit_output(session, turn)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}, 1_000
    assert audio.payload == tone <> silence
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, final: true} = final},
                   1_000

    assert :ok = Session.ack(session, final)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, request_ref: ref} =
                      completed},
                   1_000

    assert ref == output.ref
    assert :ok = Session.ack(session, completed)
  end

  test "malformed and unknown provider events fail the session explicitly" do
    for payload <- ["{", ~s({"type":"unknown.event"})] do
      {session, wire} = start_ready_session()
      provider = Session.provider(session)
      monitor = Process.monitor(provider)
      TestGPTLiveTransport.deliver_raw(wire, payload)
      assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :invalid_message}}, 1_000
    end
  end

  test "a fatal provider error fails without exposing its payload" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)
    monitor = Process.monitor(provider)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "error",
      "error" => %{
        "code" => "invalid_request_error",
        "client_event_id" => "event_1",
        "message" => "sensitive-provider-message"
      }
    })

    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :provider_failure}}, 1_000
  end

  test "normal close reasons end normally and moderation closes with a distinct reason" do
    for {reason, expected} <- [
          {"close_requested", :normal},
          {"remote_hangup", :normal},
          {"content", {:shutdown, :moderation}}
        ] do
      {session, wire} = start_ready_session()
      provider = Session.provider(session)
      monitor = Process.monitor(provider)

      TestGPTLiveTransport.deliver(wire, %{
        "type" => "session.closed",
        "reason" => reason,
        "usage" => %{"seconds" => 0.5}
      })

      assert_receive {:DOWN, ^monitor, :process, ^provider, ^expected}, 1_000

      assert_receive {:vxpipe_speech,
                      %Event{session: ^session, kind: :provider_usage, usage: usage} = report}

      assert usage == %{kind: :voice, milliseconds: 500}
      assert :ok = Session.ack(session, report)
    end
  end

  test "voice usage is delta measured while backend token counts retain their own identity" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)

    for {seconds, expected} <- [{1.25, 1_250}, {2, 2_000}, {1.5, 2_000}] do
      assert :ok =
               TestGPTLiveTransport.deliver_sync(wire, %{
                 "type" => "session.usage.updated",
                 "usage" => %{"seconds" => seconds}
               })

      assert :sys.get_state(provider).usage.voice_ms == expected
    end

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.delegation.created",
      "delegation" => %{"id" => "d_usage", "target" => "responses", "response_id" => "r_usage"}
    })

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "response.event",
      "delegation_id" => "d_usage",
      "event" => %{
        "type" => "response.completed",
        "response" => %{
          "id" => "r_usage",
          "usage" => %{"input_tokens" => 12, "output_tokens" => 7}
        }
      }
    })

    assert MapSet.member?(:sys.get_state(provider).usage.seen_responses, "r_usage")
  end

  test "closing usage emits the final voice delta and a replacement starts a new count" do
    {session, wire} = start_ready_session()

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.usage.updated",
      "usage" => %{"seconds" => 1.25}
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :provider_usage, usage: initial} = first}

    assert initial == %{kind: :voice, milliseconds: 1_250}
    assert :ok = Session.ack(session, first)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.closed",
      "reason" => "expired",
      "usage" => %{"seconds" => 1.75}
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :provider_usage, usage: closing} = final}

    assert closing == %{kind: :voice, milliseconds: 500}
    assert :ok = Session.ack(session, final)
    assert_receive {:test_gpt_live_started, replacement, _connection}
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}

    TestGPTLiveTransport.deliver(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    TestGPTLiveTransport.deliver(replacement, %{
      "type" => "session.usage.updated",
      "usage" => %{"seconds" => 0.5}
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :provider_usage, usage: next} = new_session}

    assert next == %{kind: :voice, milliseconds: 500}
    assert :ok = Session.ack(session, new_session)
  end

  test "an output burst completes after the wire falls silent" do
    {session, wire} = start_ready_session(output_gap_ms: 40)
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :response_started, turn_ref: turn} = started}

    assert :ok = Session.ack(session, started)
    assert {:ok, output} = Session.admit_output(session, turn)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = trailing}, 500
    assert :ok = Session.validate_audio(session, trailing)
    assert :ok = Session.ack_audio(session, trailing)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = last}, 500
    assert :ok = Session.validate_audio(session, last)
    assert :ok = Session.ack_audio(session, last)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, final: true} = final},
                   500

    assert :ok = Session.ack(session, final)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, request_ref: ref} =
                      completed},
                   500

    assert ref == output.ref
    assert :ok = Session.ack(session, completed)
  end

  test "malformed delegated arguments fail as a protocol error" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)
    monitor = Process.monitor(provider)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.delegation.created",
      "delegation" => %{"id" => "bad", "target" => "responses"}
    })

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "response.event",
      "delegation_id" => "bad",
      "event" => %{
        "type" => "response.output_item.done",
        "item" => %{
          "type" => "function_call",
          "status" => "completed",
          "call_id" => "bad_call",
          "name" => "echo",
          "arguments" => %{"not" => "JSON text"}
        }
      }
    })

    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :invalid_message}}, 1_000
  end

  test "expired sessions reseed only history appended through the speech allocation" do
    {session, wire} = start_ready_session()
    assert :ok = Session.append_history(session, {:caller, "The published question"})
    assert :ok = Session.append_history(session, {:agent, "The heard answer"})

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.closed", "reason" => "expired"})
    assert_receive {:test_gpt_live_started, replacement, _connection}
    assert replacement != wire

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.start", "session" => started}}

    assert started["input"] == [
             %{
               "type" => "message",
               "role" => "user",
               "content" => [%{"type" => "input_text", "text" => "The published question"}]
             },
             %{
               "type" => "message",
               "role" => "assistant",
               "content" => [%{"type" => "input_text", "text" => "The heard answer"}]
             }
           ]

    TestGPTLiveTransport.deliver(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    refute_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.commentary.append"}},
                   50

    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.input_audio.append"}}
  end

  test "connection loss after an unanswered caller turn resumes with brief commentary" do
    {session, wire} = start_ready_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "Question",
      "start_ms" => 0,
      "end_ms" => 40
    })

    for kind <- [:speech_started, :input_transcript] do
      assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}
      assert :ok = Session.ack(session, event)
    end

    silence = :binary.copy(<<0, 0>>, div(24_000 * 800, 1_000))
    assert :ok = Session.push_audio(session, silence, response_context: context)
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    for kind <- [:input_transcript, :turn_ended] do
      assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}
      assert :ok = Session.ack(session, event)
    end

    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}

    TestGPTLiveTransport.deliver(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.commentary.append", "content" => content}}

    assert String.contains?(content, "line cut out")
  end

  test "a second connection loss fails without opening another socket" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}
    TestGPTLiveTransport.disconnect(replacement)
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :reseed_failed}}, 1_000
    refute_receive {:test_gpt_live_started, _, _}, 50
  end

  test "a burst opened before a disconnect remains admissible and prompts resumption" do
    {session, wire} = start_ready_session()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}
    tone = :binary.copy(<<0, 16>>, 480)

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.output_audio.delta",
      "delta" => Base.encode64(tone)
    })

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :response_started, turn_ref: turn} = started}

    assert :ok = Session.ack(session, started)

    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}
    assert {:ok, output} = Session.admit_output(session, turn)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session, payload: payload} = audio},
                   1_000

    assert :binary.match(payload, tone) != :nomatch
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    TestGPTLiveTransport.deliver(replacement, %{
      "type" => "session.started",
      "session" => %{"id" => "s2"}
    })

    assert_receive {:test_gpt_live_control, ^replacement,
                    %{"type" => "session.commentary.append"}}

    assert output.ref != nil
  end

  test "a replacement that never acknowledges readiness fails within the reseed deadline" do
    {session, wire} = start_ready_session()
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    TestGPTLiveTransport.disconnect(wire)
    assert_receive {:test_gpt_live_started, replacement, _connection}, 1_000
    assert_receive {:test_gpt_live_control, ^replacement, %{"type" => "session.start"}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :reseed_failed}}, 6_000
  end

  test "the provider status redacts the key, prompt, history and model transcript" do
    {:ok, config} =
      GPTLive.new(
        api_key: "private-key-phrase",
        backend_model: "gpt-5.6",
        system_prompt: "private-prompt-phrase"
      )

    {session, wire} = start_ready_session(test_config: config)
    provider = Session.provider(session)
    assert :ok = Session.append_history(session, {:caller, "private-history-phrase"})

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "private-live-phrase",
      "start_ms" => 0,
      "end_ms" => 40
    })

    _ = :sys.get_state(provider)
    status = inspect(:sys.get_status(provider))
    state = inspect(:sys.get_state(provider))
    refute String.contains?(status <> state, "private-key-phrase")
    refute String.contains?(status <> state, "private-prompt-phrase")
    refute String.contains?(status <> state, "private-history-phrase")
    refute String.contains?(status <> state, "private-live-phrase")
  end

  test "provider crash reports and supervisor status omit private speech data" do
    markers = [
      "private-key-crash-sentinel",
      "private-prompt-crash-sentinel",
      "private-history-crash-sentinel",
      "private-transcript-crash-sentinel",
      "private-audio-sentinel"
    ]

    {:ok, config} =
      GPTLive.new(
        api_key: "private-key-crash-sentinel",
        backend_model: "gpt-5.6",
        system_prompt: "private-prompt-crash-sentinel"
      )

    {session, wire} = start_ready_session(test_config: config)
    provider = Session.provider(session)
    assert :ok = Session.append_history(session, {:caller, "private-history-crash-sentinel"})

    assert :ok =
             Session.push_audio(
               session,
               :binary.copy("private-audio-sentinel", 2),
               response_context: make_ref()
             )

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    TestGPTLiveTransport.deliver(wire, %{
      "type" => "session.input_transcript.delta",
      "delta" => "private-transcript-crash-sentinel",
      "start_ms" => 0,
      "end_ms" => 40
    })

    _ = :sys.get_state(provider)

    status =
      inspect(:sys.get_status(Session.tree(session)),
        limit: :infinity,
        printable_limit: :infinity
      )

    assert Enum.all?(markers, &(not String.contains?(status, &1)))
    monitor = Process.monitor(provider)

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(provider, :provider_failed)
        assert_receive {:DOWN, ^monitor, :process, ^provider, :provider_failed}, 1_000
      end)

    assert Enum.all?(markers, &(not String.contains?(logs, &1)))
  end

  defp start_ready_session(options \\ []) do
    {test_config, options} = Keyword.pop(options, :test_config)

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, default_config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")
    config = test_config || default_config

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope),
        provider: GPTLiveSession,
        options: [backend_model: "gpt-5.6"],
        private:
          [
            config: config,
            wire_module: TestGPTLiveTransport,
            wire_options: [observer: self()]
          ] ++ options,
        owner: self()
      )

    assert_receive {:test_gpt_live_started, wire, _connection}
    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}

    TestGPTLiveTransport.deliver(wire, %{"type" => "session.started", "session" => %{"id" => "s"}})

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    {session, wire}
  end
end
