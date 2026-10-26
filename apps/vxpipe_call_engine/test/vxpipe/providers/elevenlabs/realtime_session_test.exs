defmodule Vxpipe.Providers.ElevenLabs.RealtimeSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.{TestElevenLabsRealtimeAPI, TestElevenLabsRealtimeTransport}
  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeSession}

  test "native speech events complete a caller turn without a local VAD or external boundary" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0, 2, 0>>, response_context: context)
    assert_receive {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_started",
      "item_id" => "caller_1"
    })

    started = event(session, :speech_started)

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_stopped",
      "item_id" => "caller_1"
    })

    response_created(session, wire, nil, "resp_1")
    refute_received {:vxpipe_speech, %Event{kind: :response_started}}

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "resp_1",
      "delta" => "AQA="
    })

    response = event(session, :response_started)
    assert response.response_context == context
    refute response.turn_ref == started.turn_ref

    deliver(session, wire, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "caller_1",
      "transcript" => "Hello"
    })

    transcript = event(session, :input_transcript)
    ended = event(session, :turn_ended)
    assert transcript.turn_ref == started.turn_ref
    assert ended.turn_ref == started.turn_ref
    assert ended.text == "Hello"
    assert ended.endpointing == :provider_semantic
    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}
    refute RealtimeSession.input_quiescent?(Session.provider(session))
  end

  test "output requires admission and credit; completion waits for the final audio credit" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "resp_1")
    pcm = <<1, 0, 2, 0>>

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "resp_1",
      "delta" => Base.encode64(pcm)
    })

    deliver(session, wire, %{
      "type" => "response.output_audio_transcript.done",
      "response_id" => "resp_1",
      "transcript" => "Hello"
    })

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "resp_1", "status" => "completed"}
    })

    refute_received {:vxpipe_speech_audio, _}
    assert {:ok, output} = Session.admit_output(session, started.turn_ref)
    assert event(session, :output_transcript).text == "Hello"

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, payload: <<1, 0>>} = first_audio}

    provider = Session.provider(session)
    channel = :sys.get_state(provider).channel
    send(provider, {:vxpipe_speech_credit, channel, output.ref, make_ref(), :ok})
    _ = :sys.get_state(provider)
    refute_received {:vxpipe_speech_audio, _}
    assert :ok = Session.ack_audio(session, first_audio)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session, payload: ^pcm} = audio}
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}
    assert :ok = Session.ack_audio(session, audio)
    assert event(session, :output_completed).turn_ref == started.turn_ref
    assert :ok = Session.settle_output(session, output, 0)
    {second, _context} = text_response(session, wire, "resp_2")
    refute second.turn_ref == started.turn_ref
  end

  test "interrupt sends targeted cancellation and fences delayed output before replacement" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "resp_1")
    assert {:ok, _output} = Session.admit_output(session, started.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = admitted_audio}
    assert :ok = RealtimeSession.interrupt(Session.provider(session), started.turn_ref)

    assert_receive {:realtime_sent, ^wire,
                    %{"type" => "response.cancel", "response_id" => "resp_1"}}

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "resp_1",
      "delta" => "AQA="
    })

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "resp_1", "status" => "cancelled"}
    })

    refute_received {:vxpipe_speech_audio, _}
    assert event(session, :interrupted).turn_ref == started.turn_ref
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}
    assert :ok = Session.ack_audio(session, admitted_audio)
    assert event(session, :output_completed).turn_ref == started.turn_ref
  end

  test "unknown response identity fails closed instead of borrowing the latest origin" do
    {session, wire} = start_session()
    _ = text_response(session, wire, "resp_1")

    TestElevenLabsRealtimeTransport.deliver(wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "unrelated",
      "delta" => "AQA="
    })

    assert_receive {:vxpipe_speech_closed, ^session, _reason}
    refute_received {:vxpipe_speech_audio, _}
  end

  test "tools preserve context and accept one matching result before continuing" do
    {session, wire} = start_session()
    context = text_request(session, wire, "resp_1")
    refute_received {:vxpipe_speech, %Event{kind: :response_started}}

    deliver(session, wire, %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "resp_1",
      "call_id" => "call_1",
      "name" => "ping",
      "arguments" => "{}"
    })

    tool = event(session, :tool_call)
    assert tool.response_context == context
    assert is_reference(tool.turn_ref)

    assert :ok =
             RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{
               "ok" => true
             })

    assert_receive {:realtime_sent, ^wire,
                    %{
                      "type" => "conversation.item.create",
                      "item" => %{"type" => "function_call_output", "call_id" => "call_1"}
                    }}

    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "resp_1", "status" => "completed"}
    })

    _token = response_token(wire)
    refute_received {:vxpipe_speech, %Event{kind: :response_started}}
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}

    assert {:error, :stale_request} =
             RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{})
  end

  test "explicit response acceptance prevents competing microphone audio until response identity is known" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_text(session, "Hello", response_context: context)
    _ = event(session, :input_submitted)
    _ = response_token(wire)
    assert {:error, :busy} = Session.push_audio(session, <<1, 0>>, response_context: context)
    refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
  end

  test "changed authorization context closes before accepting more input after native audio" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)
    assert_receive {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}

    assert {:error, _reason} = Session.push_audio(session, <<2, 0>>, response_context: make_ref())
    assert_receive {:vxpipe_speech_closed, ^session, _reason}
    refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
  end

  test "queued explicit responses exclude microphone admission until their identity is known" do
    {session, wire} = start_session()
    {_response, context} = text_response(session, wire, "first")
    assert :ok = Session.push_text(session, "queued", response_context: context)
    _ = event(session, :input_submitted)
    assert {:error, :busy} = Session.push_audio(session, <<1, 0>>, response_context: context)
    refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
  end

  test "tool continuation waits for caller final without treating trailing PCM as a new origin" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)

    deliver(session, wire, %{"type" => "input_audio_buffer.speech_started", "item_id" => "caller"})

    _ = event(session, :speech_started)

    deliver(session, wire, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "caller"})

    response_created(session, wire, nil, "native")

    assert :ok = Session.push_audio(session, <<0, 0>>, response_context: context)

    deliver(session, wire, %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "native",
      "call_id" => "tool",
      "name" => "ping",
      "arguments" => "{}"
    })

    tool = event(session, :tool_call)
    assert :ok = RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{})

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "native", "status" => "completed"}
    })

    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}

    deliver(session, wire, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "caller",
      "transcript" => "Hello"
    })

    _ = event(session, :input_transcript)
    _ = event(session, :turn_ended)
    _ = response_token(wire)
  end

  test "older caller completion cannot clear newer audio or permit context reassignment" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_started",
      "item_id" => "caller_1"
    })

    _ = event(session, :speech_started)

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_stopped",
      "item_id" => "caller_1"
    })

    assert :ok = Session.push_audio(session, <<2, 0>>, response_context: context)

    deliver(session, wire, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "caller_1",
      "transcript" => "Hello"
    })

    _ = event(session, :input_transcript)
    _ = event(session, :turn_ended)
    refute RealtimeSession.input_quiescent?(Session.provider(session))
    assert {:error, _reason} = Session.push_audio(session, <<3, 0>>, response_context: make_ref())
    assert_receive {:vxpipe_speech_closed, ^session, _reason}
  end

  test "queued tool continuation keeps admitting the caller PCM needed for native endpointing" do
    {session, wire} = start_session()
    context = text_request(session, wire, "first")

    deliver(session, wire, %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "first",
      "call_id" => "tool",
      "name" => "ping",
      "arguments" => "{}"
    })

    tool = event(session, :tool_call)
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)

    deliver(session, wire, %{"type" => "input_audio_buffer.speech_started", "item_id" => "caller"})

    _ = event(session, :speech_started)

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "first", "status" => "completed"}
    })

    assert :ok = RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{})
    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}
    assert :ok = Session.push_audio(session, <<2, 0>>, response_context: context)

    deliver(session, wire, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "caller"})

    response_created(session, wire, nil, "native")

    deliver(session, wire, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "caller",
      "transcript" => "Hello"
    })

    _ = event(session, :input_transcript)
    _ = event(session, :turn_ended)

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "native", "status" => "completed"}
    })

    _ = response_token(wire)
  end

  test "cancelled response tool tails are ignored and accepted call IDs cannot execute twice" do
    {session, wire} = start_session()
    context = text_request(session, wire, "resp_1")

    call = %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "resp_1",
      "call_id" => "call_1",
      "name" => "ping",
      "arguments" => "{}"
    }

    deliver(session, wire, call)
    tool = event(session, :tool_call)
    assert tool.response_context == context
    assert :ok = RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{})
    deliver(session, wire, call)
    refute_received {:vxpipe_speech, %Event{kind: :tool_call}}
    assert :ok = RealtimeSession.interrupt(Session.provider(session), tool.turn_ref)
    deliver(session, wire, %{call | "call_id" => "late_call"})
    refute_received {:vxpipe_speech, %Event{kind: :tool_call}}

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "resp_1", "status" => "cancelled"}
    })

    _ = text_request(session, wire, "resp_2")
  end

  test "speech ordinals follow queued text and subsequent native audio announcements" do
    {session, wire} = start_session()
    {first, context} = text_response(session, wire, "resp_1")
    assert :ok = Session.push_text(session, "queued", response_context: context)
    _ = event(session, :input_submitted)
    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "resp_1", "status" => "completed"}
    })

    token = response_token(wire)
    response_created(session, wire, token, "queued")

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "queued",
      "delta" => "AQA="
    })

    queued = event(session, :response_started)
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_started",
      "item_id" => "caller_1"
    })

    _ = event(session, :speech_started)

    deliver(session, wire, %{
      "type" => "input_audio_buffer.speech_stopped",
      "item_id" => "caller_1"
    })

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "queued", "status" => "completed"}
    })

    response_created(session, wire, nil, "native")

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "native",
      "delta" => "AQA="
    })

    native = event(session, :response_started)

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "native", "status" => "completed"}
    })

    assert [first.response_index, queued.response_index, native.response_index] == [1, 2, 3]
  end

  for obligation <- [:caller, :native] do
    @obligation obligation
    test "missing #{@obligation} terminal evidence closes on its scoped deadline" do
      {session, wire} = start_session()
      assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())

      deliver(session, wire, %{
        "type" => "input_audio_buffer.speech_started",
        "item_id" => "caller_1"
      })

      started = event(session, :speech_started)

      deliver(session, wire, %{
        "type" => "input_audio_buffer.speech_stopped",
        "item_id" => "caller_1"
      })

      provider = Session.provider(session)

      deadline =
        if @obligation == :caller,
          do: {:caller_timeout, "caller_1", started.turn_ref},
          else: {:native_timeout, started.turn_ref}

      send(provider, deadline)
      assert_receive {:vxpipe_speech_closed, ^session, _reason}
    end
  end

  test "fixed opening never releases audio when the spoken words differ" do
    {session, wire} = start_session()

    assert :ok =
             Session.begin_opening(session, {:fixed, "Good day"}, response_context: make_ref())

    _ = event(session, :input_submitted)
    token = response_token(wire)
    response_created(session, wire, token, "opening")

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => "opening",
      "delta" => "AQA="
    })

    started = event(session, :response_started)
    assert {:ok, _output} = Session.admit_output(session, started.turn_ref)
    refute_received {:vxpipe_speech_audio, _}

    TestElevenLabsRealtimeTransport.deliver(wire, %{
      "type" => "response.output_audio_transcript.done",
      "response_id" => "opening",
      "transcript" => "Wrong words"
    })

    assert_receive {:vxpipe_speech_closed, ^session, _reason}
    refute_received {:vxpipe_speech_audio, _}
    refute_received {:vxpipe_speech, %Event{kind: :input_transcript}}
  end

  test "pre-admission rejection drops its tail and allows a fresh output" do
    {session, wire} = start_session()
    {first, _context} = text_response(session, wire, "rejected")
    assert :ok = Session.reject_response(session, first.turn_ref)

    assert_receive {:realtime_sent, ^wire,
                    %{"type" => "response.cancel", "response_id" => "rejected"}}

    deliver(session, wire, %{
      "type" => "response.done",
      "response" => %{"id" => "rejected", "status" => "cancelled"}
    })

    {second, _context} = text_response(session, wire, "accepted")
    assert {:ok, _output} = Session.admit_output(session, second.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.ack_audio(session, audio)
    refute first.turn_ref == second.turn_ref
  end

  test "owner loss reaps blocked credential preparation without a leaked socket" do
    owner = start_supervised!({Vxpipe.CallEngine.SpeechSessionOwner, self()})

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, config} = Realtime.new(api_key: "synthetic-key")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: RealtimeSession,
               options: [],
               owner: owner,
               private: [
                 config: config,
                 api_module: TestElevenLabsRealtimeAPI,
                 api_options: [observer: self()],
                 wire_module: TestElevenLabsRealtimeTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:realtime_credentials_started, worker}, 1_000
    monitor = Process.monitor(worker)
    provider = Session.provider(session)
    provider_monitor = Process.monitor(provider)
    GenServer.stop(owner)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 1_000
    refute_received {:realtime_wire, _wire}
  end

  test "readiness rejects negotiated PCM or turn-detection settings that differ from the descriptor" do
    for path_value <- [
          {["audio", "input", "format", "rate"], 16_000},
          {["audio", "output", "format", "type"], "audio/pcmu"},
          {["audio", "input", "turn_detection", "type"], "server_vad"},
          {["audio", "input", "transcription"], nil}
        ] do
      {session, wire, config} = begin_session()
      {path, value} = path_value
      negotiated = put_in(Realtime.session(config), path, value)

      TestElevenLabsRealtimeTransport.deliver(wire, %{
        "type" => "session.created",
        "session" => negotiated
      })

      assert_receive {:vxpipe_speech_closed, ^session, _reason}
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :ready}}
    end
  end

  defp start_session do
    {session, wire, config} = begin_session()
    deliver(session, wire, %{"type" => "session.created", "session" => Realtime.session(config)})
    _ = event(session, :ready)
    {session, wire}
  end

  defp begin_session do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, config} = Realtime.new(api_key: "synthetic-key")

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope),
        provider: RealtimeSession,
        options: [],
        private: [
          config: config,
          api_module: TestElevenLabsRealtimeAPI,
          wire_module: TestElevenLabsRealtimeTransport,
          wire_options: [observer: self()]
        ],
        owner: self()
      )

    assert_receive {:realtime_wire, wire}, 5_000
    refute_received {:vxpipe_speech, %Event{kind: :ready}}
    {session, wire, config}
  end

  defp text_response(session, wire, id) do
    context = text_request(session, wire, id)

    deliver(session, wire, %{
      "type" => "response.output_audio.delta",
      "response_id" => id,
      "delta" => "AQA="
    })

    {event(session, :response_started), context}
  end

  defp text_request(session, wire, id) do
    context = :sys.get_state(Session.provider(session)).context || make_ref()
    assert :ok = Session.push_text(session, "Hello", response_context: context)
    _ = event(session, :input_submitted)
    assert_receive {:realtime_sent, ^wire, %{"type" => "conversation.item.create"}}
    token = response_token(wire)
    response_created(session, wire, token, id)
    context
  end

  defp response_token(wire) do
    assert_receive {:realtime_sent, ^wire,
                    %{
                      "type" => "response.create",
                      "response" => %{"metadata" => %{"vxpipe_response" => token}}
                    }}

    token
  end

  defp response_created(session, wire, token, id),
    do:
      deliver(session, wire, %{
        "type" => "response.created",
        "response" => %{"id" => id, "metadata" => %{"vxpipe_response" => token}}
      })

  defp deliver(session, wire, message) do
    :ok = TestElevenLabsRealtimeTransport.deliver(wire, message)
    _ = :sys.get_state(Session.provider(session))
    :ok
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
