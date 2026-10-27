defmodule Vxpipe.Providers.ElevenLabs.RealtimeProgressTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.{TestElevenLabsRealtimeAPI, TestElevenLabsRealtimeTransport}
  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeSession}

  test "generation progress invalidates the previous response deadline" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "long")
    token = :sys.get_state(Session.provider(session)).active
    old = timeout_message(session, {:response, token})

    audio(session, wire, "long")
    expire_stale(session, old)
    assert {:ok, _output} = Session.admit_output(session, started.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = chunk}
    assert :ok = Session.ack_audio(session, chunk)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session}}

    expire_current(session, {:response, token})
  end

  test "each credited chunk allows progressing delivery beyond earlier response deadlines" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "long")
    token = :sys.get_state(Session.provider(session)).active
    audio(session, wire, "long")
    transcript(session, wire, "long")
    done(session, wire, "long")
    assert {:ok, output} = Session.admit_output(session, started.turn_ref)
    _ = event(session, :output_transcript)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = first}
    old = timeout_message(session, {:credit, token})
    assert :ok = Session.ack_audio(session, first)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = last}
    expire_stale(session, old)
    last_deadline = timeout_message(session, {:credit, token})
    assert :ok = Session.ack_audio(session, last)
    _ = event(session, :output_completed)
    assert :ok = Session.settle_output(session, output, 0)
    expire_stale(session, last_deadline)
  end

  test "queued explicit input has no response-start deadline until dispatched" do
    {session, wire} = start_session()
    context = text_request(session, wire, "first")
    assert :ok = Session.push_text(session, "Next", response_context: context)
    _ = event(session, :input_submitted)
    [queued] = :sys.get_state(Session.provider(session)).queue
    refute Map.has_key?(:sys.get_state(Session.provider(session)).deadlines, {:response, queued})
    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}
    done(session, wire, "first")
    assert response_token(wire) == queued
    expire_current(session, {:response, queued})
  end

  test "unrelated traffic cannot postpone a dispatched response creation timeout" do
    {session, wire} = start_session()
    assert :ok = Session.push_text(session, "Hello", response_context: make_ref())
    _ = event(session, :input_submitted)
    token = response_token(wire)
    deadline = timeout_message(session, {:response, token})
    deliver(session, wire, %{"type" => "rate_limits.updated"})
    assert timeout_message(session, {:response, token}) == deadline
    expire_current(session, {:response, token})
  end

  test "provider progress cannot postpone withheld output credit" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "held")
    token = :sys.get_state(Session.provider(session)).active
    assert {:ok, _output} = Session.admit_output(session, started.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session}}
    deadline = timeout_message(session, {:credit, token})
    audio(session, wire, "held")
    transcript(session, wire, "held")
    assert timeout_message(session, {:credit, token}) == deadline
    expire_current(session, {:credit, token})
  end

  test "output credit cannot postpone stalled provider generation" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "stalled")
    token = :sys.get_state(Session.provider(session)).active
    assert {:ok, _output} = Session.admit_output(session, started.turn_ref)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = chunk}
    deadline = timeout_message(session, {:response, token})
    assert :ok = Session.ack_audio(session, chunk)
    _ = :sys.get_state(Session.provider(session))
    assert timeout_message(session, {:response, token}) == deadline
    expire_current(session, {:response, token})
  end

  test "audible completion waits for final transcript independently of output admission" do
    {session, wire} = start_session()
    {_started, _context} = text_response(session, wire, "missing-final")
    token = :sys.get_state(Session.provider(session)).active
    generation = timeout_message(session, {:response, token})
    done(session, wire, "missing-final")
    expire_stale(session, generation)
    expire_current(session, {:response, token})
  end

  test "discarded tails and repeated cancellation cannot postpone cancellation completion" do
    {session, wire} = start_session()
    {started, _context} = text_response(session, wire, "cancelled")
    provider = Session.provider(session)
    token = :sys.get_state(provider).active
    generation = timeout_message(session, {:response, token})
    assert :ok = RealtimeSession.interrupt(provider, started.turn_ref)
    expire_stale(session, generation)
    cancellation = timeout_message(session, {:response, token})
    audio(session, wire, "cancelled")
    transcript(session, wire, "cancelled")
    assert :ok = RealtimeSession.interrupt(provider, started.turn_ref)
    assert timeout_message(session, {:response, token}) == cancellation
    expire_current(session, {:response, token})
  end

  test "resumed speech suspends native creation while preserving its original identity" do
    {session, wire} = start_session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: context)
    caller_started(session, wire, "first")
    first = event(session, :speech_started)
    caller_stopped(session, wire, "first")
    final_input(session, wire, "first")
    old = timeout_message(session, {:native, first.turn_ref})

    caller_started(session, wire, "resumed")
    resumed = event(session, :speech_started)
    expire_stale(session, old)
    assert :ok = Session.push_audio(session, <<2, 0>>, response_context: context)
    response_created(session, wire, nil, "first-response")
    audio(session, wire, "first-response")
    assert event(session, :response_started).response_context == context
    caller_stopped(session, wire, "resumed")
    final_input(session, wire, "resumed")
    state = :sys.get_state(Session.provider(session))
    refute Map.has_key?(state.deadlines, {:native, resumed.turn_ref})
    transcript(session, wire, "first-response")
    done(session, wire, "first-response")
    expire_current(session, {:native, resumed.turn_ref})
  end

  test "another native stop without the earlier response identity still fails closed" do
    {session, wire} = start_session()
    assert :ok = Session.push_audio(session, <<1, 0>>, response_context: make_ref())
    caller_started(session, wire, "first")
    _ = event(session, :speech_started)
    caller_stopped(session, wire, "first")
    caller_started(session, wire, "second")
    _ = event(session, :speech_started)

    TestElevenLabsRealtimeTransport.deliver(wire, %{
      "type" => "input_audio_buffer.speech_stopped",
      "item_id" => "second"
    })

    assert_receive {:vxpipe_speech_closed, ^session, _reason}
  end

  test "a completed tool-only response does not acquire a missing speech transcript deadline" do
    {session, wire} = start_session()
    _ = text_request(session, wire, "tool-only")
    token = :sys.get_state(Session.provider(session)).active

    deliver(session, wire, %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "tool-only",
      "call_id" => "call",
      "name" => "ping",
      "arguments" => "{}"
    })

    tool = event(session, :tool_call)
    old = timeout_message(session, {:response, token})
    done(session, wire, "tool-only")
    expire_stale(session, old)
    state = :sys.get_state(Session.provider(session))
    refute Map.has_key?(state.deadlines, {:response, token})
    assert :ok = RealtimeSession.send_tool_result(Session.provider(session), tool.call_ref, %{})
    _ = response_token(wire)
  end

  defp caller_started(session, wire, id),
    do: deliver(session, wire, %{"type" => "input_audio_buffer.speech_started", "item_id" => id})

  defp caller_stopped(session, wire, id),
    do: deliver(session, wire, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => id})

  defp final_input(session, wire, id) do
    deliver(session, wire, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => id,
      "transcript" => "Hello"
    })

    _ = event(session, :input_transcript)
    _ = event(session, :turn_ended)
  end

  defp timeout_message(session, key) do
    state = :sys.get_state(Session.provider(session))
    {:realtime_timeout, key, Map.fetch!(state.deadlines, key).ref}
  end

  defp expire_stale(session, message) do
    send(Session.provider(session), message)
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech_closed, ^session, _reason}
  end

  defp expire_current(session, key) do
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    send(provider, timeout_message(session, key))
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    assert_receive {:vxpipe_speech_closed, ^session, _reason}
  end

  defp audio(session, wire, id),
    do:
      deliver(session, wire, %{
        "type" => "response.output_audio.delta",
        "response_id" => id,
        "delta" => "AQA="
      })

  defp transcript(session, wire, id),
    do:
      deliver(session, wire, %{
        "type" => "response.output_audio_transcript.done",
        "response_id" => id,
        "transcript" => "Hello"
      })

  defp done(session, wire, id),
    do:
      deliver(session, wire, %{
        "type" => "response.done",
        "response" => %{"id" => id, "status" => "completed"}
      })

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
