defmodule Vxpipe.CallEngine.CallDefinition.OpeningAudioCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, Error}
  alias Vxpipe.CallEngine.CallDefinition.OpeningAudio

  test "pins supported text and HTTPS file sources into the resolved plan" do
    assert CallDefinition.schema_version() == "20260911.01"

    for {input, expected} <- [
          {%{type: "text", text: "This call may be recorded."},
           %OpeningAudio{type: :text, text: "This call may be recorded.", url: nil}},
          {%{type: "file_url", url: "https://assets.example.test/opening.wav"},
           %OpeningAudio{
             type: :file_url,
             text: nil,
             url: "https://assets.example.test/opening.wav"
           }}
        ] do
      assert {:ok, definition} =
               definition_input()
               |> Map.put(:opening_audio, input)
               |> CallDefinition.new(resource_id: "support", revision: 7)

      assert definition.opening_audio == expected
      assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation(), registries())
      assert plan.opening_audio == expected
    end
  end

  test "omission adds no opening audio and malformed sources fail at their exact path" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 7)

    assert definition.opening_audio == nil

    for {opening_audio, path} <- [
          {%{type: "text", text: ""}, ["opening_audio", "text"]},
          {%{type: "text", text: "hello", url: "https://example.test/a.wav"},
           ["opening_audio", "url"]},
          {%{type: "file_url", url: "http://example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://user@example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://example.test/a.wav#part"}, ["opening_audio", "url"]},
          {%{type: "unknown", text: "hello"}, ["opening_audio", "type"]}
        ] do
      assert {:error, %Error{code: :invalid_call_definition, details: %{"path" => ^path}}} =
               definition_input()
               |> Map.put(:opening_audio, opening_audio)
               |> CallDefinition.new(resource_id: "support", revision: 7)
    end
  end

  defp definition_input do
    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          prompt: "Answer clearly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp invocation do
    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "support", revision: 7},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    invocation
  end

  defp registries do
    %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :test_model,
          options: %{model: "test"}
        }
      },
      host_tools: %{}
    }
  end
end
