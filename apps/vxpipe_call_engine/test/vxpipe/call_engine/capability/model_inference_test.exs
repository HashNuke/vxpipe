defmodule Vxpipe.CallEngine.Capability.ModelInferenceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.ModelInference
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.TestModelInferenceProvider
  alias Vxpipe.CallEngine.Tool.Call

  test "rejects unsolicited tool calls without executing them" do
    capability = start_capability()
    command = command("unsolicited-tool", "hello")
    call = %Call{id: "tool-call-unsolicited", name: "get_current_time", arguments: %{}}

    assert :ok = ModelInference.respond(capability, command)
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:tool_calls, [call]}})

    refute_receive {:vxpipe_capability_tool_started, ^capability, ^command, ^call}

    assert_receive {:vxpipe_capability_failed, ^capability, ^command, :invalid_response}
  end

  test "rejects unsolicited streaming tool calls without executing them" do
    capability = start_capability(provider_config: %{observer: self(), streaming: true})
    command = command("unsolicited-streaming-tool", "hello")
    call = %Call{id: "tool-call-stream", name: "get_current_time", arguments: %{}}

    assert :ok = ModelInference.respond(capability, command)
    assert_receive {:test_stream_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:tool_calls, [call]}})

    refute_receive {:vxpipe_capability_tool_started, ^capability, ^command, ^call}

    assert_receive {:vxpipe_capability_failed, ^capability, ^command, :invalid_response}
  end

  test "emits complete sentences before a streaming response completes" do
    capability = start_capability(provider_config: %{observer: self(), streaming: true})
    command = command("streamed", "tell me something")

    assert :ok = ModelInference.respond(capability, command)
    assert_receive {:test_stream_model_inference_request, request, _messages}

    emit_chunk(request, "First sentence. Sec")
    assert_receive {:vxpipe_capability_text, ^capability, ^command, "First sentence."}
    refute_receive {:vxpipe_capability_text_complete, ^capability, ^command}

    emit_chunk(request, "ond sentence!")
    send(request, {:test_model_inference_reply, :ok})

    assert_receive {:vxpipe_capability_text, ^capability, ^command, "Second sentence!"}
    assert_receive {:vxpipe_capability_text_complete, ^capability, ^command}
  end

  test "routes a non-streaming provider through one segment and terminal completion" do
    capability = start_capability()
    command = command("buffered", "hello")

    assert :ok = ModelInference.respond(capability, command)
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:ok, "Buffered answer."}})

    assert_receive {:vxpipe_capability_text, ^capability, ^command, "Buffered answer."}
    assert_receive {:vxpipe_capability_text_complete, ^capability, ^command}
  end

  test "serializes requests and includes the prompt and completed history" do
    capability = start_capability(maximum_pending_requests: 1, maximum_context_turns: 2)
    first = command("first", "hello")
    second = command("second", "what did I say?")
    third = command("third", "one request too many")

    assert :ok = ModelInference.respond(capability, first)

    assert_receive {:test_model_inference_request, first_request,
                    [
                      %Message{role: :system, content: "Be concise."},
                      %Message{role: :user, content: "hello"}
                    ]}

    assert :ok = ModelInference.respond(capability, second)
    assert {:error, :queue_full} = ModelInference.respond(capability, third)
    refute_receive {:test_model_inference_request, _request, _messages}

    send(first_request, {:test_model_inference_reply, {:ok, "Hello there."}})

    assert_receive {:vxpipe_capability_text, ^capability, ^first, "Hello there."}

    assert_receive {:test_model_inference_request, second_request,
                    [
                      %Message{role: :system, content: "Be concise."},
                      %Message{role: :user, content: "hello"},
                      %Message{role: :assistant, content: "Hello there."},
                      %Message{role: :user, content: "what did I say?"}
                    ]}

    send(second_request, {:test_model_inference_reply, {:ok, "You said hello."}})

    assert_receive {:vxpipe_capability_text, ^capability, ^second, "You said hello."}
  end

  test "bounds completed context by whole turns" do
    capability = start_capability(maximum_context_turns: 1)

    first = command("first", "alpha")
    assert :ok = ModelInference.respond(capability, first)
    assert_receive {:test_model_inference_request, first_request, _messages}
    send(first_request, {:test_model_inference_reply, {:ok, "one"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^first, "one"}

    second = command("second", "beta")
    assert :ok = ModelInference.respond(capability, second)
    assert_receive {:test_model_inference_request, second_request, _messages}
    send(second_request, {:test_model_inference_reply, {:ok, "two"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^second, "two"}

    third = command("third", "gamma")
    assert :ok = ModelInference.respond(capability, third)

    assert_receive {:test_model_inference_request, third_request,
                    [
                      %Message{role: :system, content: "Be concise."},
                      %Message{role: :user, content: "beta"},
                      %Message{role: :assistant, content: "two"},
                      %Message{role: :user, content: "gamma"}
                    ]}

    send(third_request, {:test_model_inference_reply, {:ok, "three"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^third, "three"}
  end

  test "reports provider failure and remains available for the next turn" do
    capability = start_capability()
    failed = command("failed", "fail once")

    assert :ok = ModelInference.respond(capability, failed)
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:error, :upstream_unavailable}})

    assert_receive {:vxpipe_capability_failed, ^capability, ^failed, :provider_unavailable}

    recovered = command("recovered", "try again")
    assert :ok = ModelInference.respond(capability, recovered)
    assert_receive {:test_model_inference_request, recovered_request, _messages}
    send(recovered_request, {:test_model_inference_reply, {:ok, "recovered"}})

    assert_receive {:vxpipe_capability_text, ^capability, ^recovered, "recovered"}
  end

  test "rejects non-UTF-8 provider output without losing the capability" do
    capability = start_capability()
    invalid = command("invalid", "invalid output")

    assert :ok = ModelInference.respond(capability, invalid)
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:ok, <<255>>}})

    assert_receive {:vxpipe_capability_failed, ^capability, ^invalid, :invalid_response}

    recovered = command("valid", "try again")
    assert :ok = ModelInference.respond(capability, recovered)
    assert_receive {:test_model_inference_request, recovered_request, _messages}
    send(recovered_request, {:test_model_inference_reply, {:ok, "valid output"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^recovered, "valid output"}
  end

  test "times out one provider request and advances the queue" do
    capability = start_capability(request_timeout_ms: 250)
    timed_out = command("timed-out", "take too long")
    next = command("next", "continue")

    assert :ok = ModelInference.respond(capability, timed_out)
    assert_receive {:test_model_inference_request, _request, _messages}
    assert :ok = ModelInference.respond(capability, next)

    assert_receive {:vxpipe_capability_failed, ^capability, ^timed_out, :provider_timeout}, 1_000
    assert_receive {:test_model_inference_request, next_request, _messages}
    send(next_request, {:test_model_inference_reply, {:ok, "continued"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^next, "continued"}
  end

  test "interrupts in-flight and queued requests before accepting replacement work" do
    capability = start_capability()
    current = command("current", "keep talking")
    queued = command("queued", "wait your turn")
    replacement = command("replacement", "new topic")

    assert :ok = ModelInference.respond(capability, current)
    assert_receive {:test_model_inference_request, request, _messages}
    request_monitor = Process.monitor(request)
    assert :ok = ModelInference.respond(capability, queued)

    assert {:ok, [^current, ^queued]} = ModelInference.interrupt(capability, [])
    assert_receive {:DOWN, ^request_monitor, :process, ^request, _reason}

    assert :ok = ModelInference.respond(capability, replacement)

    assert_receive {:test_model_inference_request, replacement_request,
                    [
                      %Message{role: :system, content: "Be concise."},
                      %Message{role: :user, content: "new topic"}
                    ]}

    send(replacement_request, {:test_model_inference_reply, {:ok, "new answer"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^replacement, "new answer"}
    refute_receive {:vxpipe_capability_text, ^capability, ^current, _text}
    refute_receive {:vxpipe_capability_text, ^capability, ^queued, _text}
  end

  test "removes interrupted completed turns from subsequent model context" do
    capability = start_capability()
    completed = command("completed", "old topic")

    assert :ok = ModelInference.respond(capability, completed)
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:ok, "old answer"}})
    assert_receive {:vxpipe_capability_text, ^capability, ^completed, "old answer"}

    assert {:ok, []} =
             ModelInference.interrupt(
               capability,
               [{"connection-test", "completed", completed.id}]
             )

    replacement = command("replacement", "new topic")
    assert :ok = ModelInference.respond(capability, replacement)

    assert_receive {:test_model_inference_request, _request,
                    [
                      %Message{role: :system, content: "Be concise."},
                      %Message{role: :user, content: "new topic"}
                    ]}
  end

  defp start_capability(overrides \\ []) do
    task_supervisor = start_supervised!({Task.Supervisor, []})

    provider_config = Keyword.get(overrides, :provider_config, %{observer: self()})
    overrides = Keyword.delete(overrides, :provider_config)

    options =
      Keyword.merge(
        [
          owner: self(),
          participant_id: "agent-test",
          provider: {TestModelInferenceProvider, provider_config},
          system_prompt: "Be concise.",
          maximum_context_turns: 4,
          maximum_pending_requests: 2,
          maximum_output_bytes: 65_536,
          request_timeout_ms: 1_000,
          task_supervisor: task_supervisor
        ],
        overrides
      )

    start_supervised!({ModelInference, options})
  end

  defp emit_chunk(request, chunk) do
    send(request, {:test_model_inference_chunk, chunk, self()})
    assert_receive {:test_model_inference_chunk_result, :ok}
  end

  defp command(correlation_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: "room-test",
               incarnation_id: "rinc-test",
               participant_id: "participant-test",
               connection_id: "connection-test",
               correlation_id: correlation_id,
               content: content,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end
end
