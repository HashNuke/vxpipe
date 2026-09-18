defmodule Vxpipe.CallEngine.CallSpec.OpeningAudioCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler, Error}
  alias Vxpipe.CallEngine.CallSpec.OpeningAudio

  test "resolves the opening's explicit TTS selection with a human initial receiver" do
    input =
      call_spec_input()
      |> put_in([:participants, "reception"], %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"}
      })
      |> Map.put(:opening_audio, %{
        type: "text",
        text: "This call may be recorded.",
        text_to_speech: %{provider: "morse", model: "morse"}
      })

    assert {:ok, call_spec} = CallSpec.new(input, resource_id: "support", revision: 7)
    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation(), registries())
    assert plan.opening_audio.text_to_speech.provider == "morse"
    assert plan.opening_audio.text_to_speech.model == "morse"
    assert Map.fetch!(plan.participants, "reception").capabilities.text_to_speech == nil
  end

  test "text opening requires its own selection even when the agent has a default voice" do
    input =
      call_spec_input()
      |> put_in([:defaults, :capabilities, :text_to_speech], %{provider: "morse", model: "morse"})
      |> Map.put(:opening_audio, %{type: "text", text: "Notice"})

    assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
             CallSpec.new(input, resource_id: "support", revision: 7)
  end

  test "rejects legacy, wrong-kind, and malformed opening selections without inheriting defaults" do
    for selection <- [
          "missing",
          "test-model",
          nil,
          "",
          false,
          %{provider: "fixture", model: "test"}
        ] do
      input =
        Map.put(call_spec_input(), :opening_audio, %{
          type: "text",
          text: "Notice",
          text_to_speech: selection
        })

      assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
               CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "pins supported text and HTTPS file sources into the resolved plan" do
    assert CallSpec.schema_version() == "20260915.01"

    for {input, expected} <- [
          {%{
             type: "text",
             text: "This call may be recorded.",
             text_to_speech: %{provider: "morse", model: "morse"}
           },
           %OpeningAudio{
             type: :text,
             text: "This call may be recorded.",
             url: nil,
             text_to_speech: %Vxpipe.CallEngine.CallSpec.CapabilitySelection{
               kind: :text_to_speech,
               provider: "morse",
               model: "morse",
               credential_name: nil,
               options: %{},
               provider_options: %{}
             }
           }},
          {%{type: "file_url", url: "https://assets.example.test/opening.wav"},
           %OpeningAudio{
             type: :file_url,
             text: nil,
             url: "https://assets.example.test/opening.wav"
           }}
        ] do
      assert {:ok, call_spec} =
               call_spec_input()
               |> Map.put(:opening_audio, input)
               |> CallSpec.new(resource_id: "support", revision: 7)

      assert call_spec.opening_audio == expected
      assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation(), registries())
      assert plan.opening_audio.type == expected.type
      assert plan.opening_audio.text == expected.text
      assert plan.opening_audio.url == expected.url
    end
  end

  test "omission adds no opening audio and malformed sources fail at their exact path" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert call_spec.opening_audio == nil

    for {opening_audio, path} <- [
          {%{type: "text", text: ""}, ["opening_audio", "text"]},
          {%{type: "text", text: "hello", url: "https://example.test/a.wav"},
           ["opening_audio", "url"]},
          {%{type: "file_url", url: "http://example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://user@example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://example.test/a.wav#part"}, ["opening_audio", "url"]},
          {%{
             type: "file_url",
             url: "https://example.test/a.wav",
             text_to_speech: %{provider: "morse", model: "morse"}
           }, ["opening_audio", "text_to_speech"]},
          {%{type: "unknown", text: "hello"}, ["opening_audio", "type"]}
        ] do
      assert {:error, %Error{code: :invalid_call_spec, details: %{"path" => ^path}}} =
               call_spec_input()
               |> Map.put(:opening_audio, opening_audio)
               |> CallSpec.new(resource_id: "support", revision: 7)
    end
  end

  defp call_spec_input do
    %{
      schema_version: CallSpec.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
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
                 call_spec: %{id: "support", revision: 7},
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
      host_tools: %{}
    }
  end
end
