defmodule Vxpipe.CallEngine.TestTurnCall do
  @moduledoc "Inline call setup shared by model and speech turn contract tests."

  import ExUnit.Assertions

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, TestCallStartup}

  def definition(options \\ []) do
    input =
      if Keyword.get(options, :speech_to_text, false),
        do: %{speech_to_text: speech("flux-general-en", "opus")},
        else: %{}

    model = %{model_inference: %{provider: "fixture", model: "test:turns"}}

    output =
      if Keyword.get(options, :text_to_speech, false),
        do: Map.put(model, :text_to_speech, speech("flux-haley-en", "linear16")),
        else: model

    caller = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: input
    }

    participants = %{
      "caller" => caller,
      "receiver" => %{
        type: "agent",
        prompt: "Answer as a compact test assistant.",
        first_message: %{mode: "wait_for_input"},
        capabilities: output,
        tools: %{},
        transfers: []
      }
    }

    participants =
      if Keyword.get(options, :second_human, false),
        do: Map.put(participants, "second", caller),
        else: participants

    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      call_variables: %{sections: %{}},
      participants: participants,
      limits: %{max_duration_ms: 60_000}
    }
  end

  def start(room_id, options \\ []) do
    assert {:ok, definition} =
             CallDefinition.new(definition(options), resource_id: "turn-definition", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "turn-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: room_id <> "-call",
               room_id: room_id
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, %{host_tools: %{}})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    {plan, room, Map.fetch!(plan.participants, plan.entry_caller)}
  end

  defp speech(model, encoding),
    do: %{provider: "deepgram", model: model, options: %{encoding: encoding, sample_rate: 48_000}}
end
