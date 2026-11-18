defmodule Vxpipe.AgentRuntime.LiveUniversalConversation do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.AgentRuntime.{
    Event,
    Input,
    Message,
    Protocol,
    ProviderSelection,
    Session,
    ToolDescriptor
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @long_reply "The Northstar office opens at 9 in the morning. " <>
                "It closes at 5 in the afternoon. These hours apply Monday through Friday."

  def run(provider, streaming, strategy \\ :configured, generation_overrides \\ []) do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:req_llm, :request, :stop],
        &Vxpipe.AgentRuntime.LiveObservedProvider.observe_transport/4,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    selection = Vxpipe.Providers.LiveModels.llm(provider)

    assert {:ok, options} =
             ProviderSelection.translate(
               provider,
               selection.model,
               %{"max_tokens" => 2_048},
               selection.specific
             )

    assert {:ok, config} =
             options
             |> Keyword.put(:api_key, System.fetch_env!(selection.env))
             |> Keyword.put(:streaming, streaming)
             |> Provider.new()

    config = if strategy == :configured, do: config, else: %{config | reply_strategy: strategy}

    config = %{
      config
      | generation_options: Keyword.merge(config.generation_options, generation_overrides)
    }

    pending = start_supervised!({Agent, fn -> [] end}, id: make_ref())
    tools = Enum.map(["lookup", "hangup"], &tool(&1, pending))
    {:ok, protocol} = Protocol.capture()
    {:ok, instructions} = Protocol.instructions(protocol, instructions(), :llm)

    session =
      start_supervised!(
        {Session,
         instructions: instructions,
         history_mode: :host_settled,
         reply_protocol: :mode_message_v1,
         model_provider: Vxpipe.AgentRuntime.LiveObservedProvider,
         model: config,
         tools: tools,
         executor: Vxpipe.AgentRuntime.LiveConversationExecutor,
         pending_context_source: {Vxpipe.AgentRuntime.LiveConversationPendingContext, pending},
         event_destination: self(),
         request_timeout_ms: 60_000},
        id: make_ref()
      )

    evidence = %{
      provider: provider,
      model: selection.model,
      streaming: streaming,
      tool_choice: Keyword.get(config.generation_options, :tool_choice, :default),
      strategy: config.reply_strategy
    }

    assert %{agent_mode: :speaker, message: greeting} =
             step(session, "short", "Please greet me briefly.", evidence)

    assert is_binary(greeting) and greeting != ""

    assert %{agent_mode: :speaker, message: long} =
             step(
               session,
               "long",
               "Please say exactly these three sentences: " <> @long_reply,
               evidence
             )

    assert byte_size(long) >= 80

    assert %{agent_mode: :listener, message: nil} =
             step(
               session,
               "silent",
               "Please wait silently while I check my sample reference.",
               evidence
             )

    assert %{agent_mode: :listener, message: cue} =
             step(session, "cue", "I am dictating. Say Go ahead and keep listening.", evidence)

    assert String.downcase(cue) =~ "go ahead"
    refute_received {:tool_submitted, _, _, _, _, _}

    assert %{message: acknowledgment} =
             step(
               session,
               "lookup",
               "Call lookup exactly once with reference DEMO-42. First wait for its native result before speaking.",
               evidence
             )

    assert is_binary(acknowledgment) and acknowledgment != ""
    assert_receive {:tool_submitted, _, :lookup, %{"reference" => "DEMO-42"}, _, invocation}
    refute_received {:tool_submitted, _, _, _, _, _}

    %{message: arithmetic} =
      step(
        session,
        "unrelated",
        "While that runs, what is two plus two? Reply with exactly Four.",
        evidence
      )

    assert arithmetic =~ "4" or String.downcase(arithmetic) =~ "four"
    Agent.update(pending, fn _ -> [] end)

    %{message: completed} =
      step(
        session,
        "completion",
        "Tool lookup invocation #{invocation} completed successfully: reference DEMO-42 has status READY. Reply with exactly: DEMO-42 is READY.",
        evidence,
        :engine
      )

    assert String.upcase(completed) =~ "READY"
    {:ok, idle} = Input.platform(:idle_timeout, %{}, :listener)
    assert %{agent_mode: :listener, message: nil} = step(session, "idle", idle, evidence, :engine)
    refute_received {:tool_submitted, _, _, _, _, _}

    correlation = %{request_id: "cancel"}
    started = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        Session.request(
          session,
          participant("Write the integers from one to two thousand."),
          correlation
        )
      end)

    assert_receive {:agent_runtime_event,
                    %Event{kind: :model_attempt_started, correlation: ^correlation} = attempt},
                   5_000

    assert :ok = Session.cancel(session)
    assert {:ok, %{status: :cancelled}} = Task.await(task, 5_000)
    assert :ok = Session.settle_output(session, correlation, nil)
    elapsed = System.monotonic_time(:millisecond) - started
    record(evidence, "cancel", elapsed, :cancelled, [attempt | events()])

    assert %{agent_mode: :speaker, message: ready} =
             step(
               session,
               "after_cancel",
               "Resume answering now. Use speaker mode and reply with exactly READY.",
               evidence
             )

    assert String.upcase(ready) =~ "READY"
    refute_received {:tool_submitted, _, _, _, _, _}
    :ok
  end

  defp step(session, name, input, evidence, origin \\ :caller) do
    correlation = %{request_id: name}
    started = System.monotonic_time(:millisecond)

    result =
      if origin == :engine,
        do: Session.continue(session, input, correlation),
        else: Session.request(session, participant(input), correlation)

    elapsed = System.monotonic_time(:millisecond) - started

    outcome =
      case result do
        {:ok, %{status: :completed}} -> :completed
        {:ok, %{reason: reason}} -> reason
        {:error, reason} -> reason
      end

    observed = events()

    dialogue =
      try do
        assert {:ok, %{status: :completed, dialogue: dialogue}} = result
        validate_dialogue!(name, dialogue)
        record(evidence, name, elapsed, {outcome, :passed}, observed)
        dialogue
      rescue
        error ->
          record(evidence, name, elapsed, {outcome, :failed}, observed)
          reraise error, __STACKTRACE__
      end

    spoken =
      if is_nil(dialogue.message) do
        nil
      else
        {:ok, spoken} = Message.spoken_assistant("agent", dialogue.message, dialogue.agent_mode)
        spoken
      end

    assert :ok = Session.settle_output(session, correlation, spoken)
    dialogue
  end

  defp events(acc \\ []) do
    receive do
      {:agent_runtime_event, event} -> events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp record(evidence, step, elapsed, outcome, events) do
    {outcome, semantic_outcome} =
      case outcome do
        {runtime, semantic} -> {runtime, semantic}
        runtime -> {runtime, :not_applicable}
      end

    evidence = Map.update!(evidence, :strategy, &Atom.to_string/1)

    usage =
      for %Event{kind: :model_usage, data: %{usage: usage}} <- events,
          do: Map.take(usage, [:input_tokens, :output_tokens, :reasoning_tokens, :total_tokens])

    attempts = Enum.count(events, &(&1.kind == :model_attempt_started))

    IO.puts(
      "UNIVERSAL_REPLY_EVIDENCE " <>
        JSON.encode!(
          Map.merge(evidence, %{
            step: step,
            elapsed_ms: elapsed,
            outcome: to_string(outcome),
            semantic_outcome: to_string(semantic_outcome),
            model_attempts: attempts,
            usage: usage
          })
        )
    )
  end

  defp validate_dialogue!("short", dialogue) do
    assert dialogue.agent_mode == :speaker
    assert is_binary(dialogue.message) and dialogue.message != ""
  end

  defp validate_dialogue!("long", dialogue) do
    assert dialogue.agent_mode == :speaker
    assert normalized(dialogue.message) == normalized(@long_reply)
  end

  defp validate_dialogue!(name, dialogue) when name in ["silent", "idle"] do
    assert dialogue.agent_mode == :listener and is_nil(dialogue.message)
  end

  defp validate_dialogue!("cue", dialogue) do
    assert dialogue.agent_mode == :listener
    assert normalized(dialogue.message) == "go ahead"
  end

  defp validate_dialogue!(name, dialogue) do
    expected = %{
      "lookup" => "the lookup is running",
      "unrelated" => "four",
      "completion" => "demo-42 is ready",
      "after_cancel" => "ready"
    }

    assert dialogue.agent_mode == :speaker
    assert normalized(dialogue.message) == Map.fetch!(expected, name)
  end

  defp normalized(text),
    do: text |> String.downcase() |> String.trim() |> String.trim_trailing(".")

  defp participant(text) do
    {:ok, input} = Input.participant("caller", text, :listener)
    input
  end

  defp tool(name, pending) do
    schema =
      if name == "lookup",
        do: %{
          "type" => "object",
          "properties" => %{"reference" => %{"type" => "string"}},
          "required" => ["reference"],
          "additionalProperties" => false
        },
        else: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}

    identity = if name == "lookup", do: :lookup, else: :hangup

    {:ok, tool} =
      ToolDescriptor.new(
        name: name,
        description:
          if(name == "lookup",
            do: "Look up a sample reference asynchronously.",
            else: "End the call only when explicitly requested."
          ),
        input_schema: schema,
        binding: %{test_owner: self(), identity: identity, pending: pending}
      )

    tool
  end

  defp instructions do
    "You are the synthetic Northstar office receptionist. Office hours are 9 to 5 Monday to Friday. " <>
      "Use speaker mode for answers. When asked to wait silently or on idle_timeout, use listener mode with null message. " <>
      "When asked to say Go ahead and keep listening, use listener mode with message Go ahead. " <>
      "Use lookup exactly once when explicitly asked. After its native result reports running, say exactly The lookup is running. " <>
      "Do not give that acknowledgment before the native tool result, or claim that the lookup has completed. " <>
      "Never repeat lookup for a running reference. Report a later trusted completion when it arrives. " <>
      "Do not call hangup unless explicitly requested. Keep responses concise except when asked for three sentences."
  end
end
