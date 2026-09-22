defmodule Vxpipe.CallEngine.CallSpec.STSExampleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}

  test "morse STS call-spec example compiles to an agent STS selection without a text model" do
    source = %{
      schema_version: "20260915.01",
      name: "Morse STS example",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly with Morse speech.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          capabilities: %{
            speech_to_speech: %{provider: "morse", model: "morse", options: %{}}
          }
        }
      }
    }

    assert {:ok, call_spec} = CallSpec.new(source, resource_id: "sts-example", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-example", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-example",
               actor_id: "operator-sts-example"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    assistant = plan.participants["assistant"]
    assert assistant.capabilities.speech_to_speech.provider == "morse"
    assert assistant.capabilities.model_inference == nil
    assert assistant.capabilities.text_to_speech == nil

    assert File.exists?(
             Path.join([File.cwd!(), "..", "..", "examples", "call-specs", "sts-morse.json"])
           )
  end
end
