defmodule Vxpipe.CallEngine.CallSpec.STSSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}

  test "agent supports text, STS provider-transcript, and STS plus output STT modes" do
    assert {:ok, plan} =
             compile_with_agent_caps(%{
               speech_to_speech: %{provider: "morse", model: "morse", options: %{}}
             })

    caps = plan.participants["assistant"].capabilities
    assert caps.speech_to_speech.provider == "morse"
    assert caps.model_inference == nil
    assert caps.text_to_speech == nil
    assert caps.output_speech_to_text == nil

    assert {:ok, plan} =
             compile_with_agent_caps(%{
               speech_to_speech: %{
                 provider: "morse",
                 model: "morse",
                 options: %{output_transcript: false}
               },
               output_speech_to_text: %{provider: "morse", model: "morse", options: %{}}
             })

    caps = plan.participants["assistant"].capabilities
    assert caps.speech_to_speech.provider == "morse"
    assert caps.output_speech_to_text.provider == "morse"
  end

  test "agent output STT is required exactly when STS lacks output transcription" do
    assert {:error, _} =
             compile_with_agent_caps(%{
               speech_to_speech: %{
                 provider: "morse",
                 model: "morse",
                 options: %{output_transcript: false}
               }
             })

    assert {:error, _} =
             compile_with_agent_caps(%{
               speech_to_speech: %{provider: "morse", model: "morse", options: %{}},
               output_speech_to_text: %{provider: "morse", model: "morse", options: %{}}
             })
  end

  test "rejects STS combined with text model path and output STT without STS" do
    assert {:error, _} =
             compile_with_agent_caps(%{
               model_inference: %{provider: "fixture", model: "echo", options: %{}},
               speech_to_speech: %{provider: "morse", model: "morse", options: %{}}
             })

    assert {:error, _} =
             compile_with_agent_caps(%{
               speech_to_speech: %{provider: "morse", model: "morse", options: %{}},
               text_to_speech: %{provider: "morse", model: "morse", options: %{}}
             })

    assert {:error, _} =
             compile_with_agent_caps(%{
               model_inference: %{provider: "fixture", model: "echo", options: %{}},
               output_speech_to_text: %{provider: "morse", model: "morse", options: %{}}
             })
  end

  test "turn-control selection is independent of transcript sources" do
    for turn_control <- ["provider", "external", "hybrid"] do
      assert {:ok, plan} =
               compile_with_agent_caps(
                 %{
                   speech_to_speech: %{
                     provider: "morse",
                     model: "morse",
                     options: %{turn_control: turn_control}
                   }
                 },
                 %{speech_to_text: %{provider: "morse", model: "morse", options: %{}}}
               )

      caps = plan.participants["assistant"].capabilities
      assert caps.speech_to_speech.provider == "morse"
      assert caps.speech_to_speech.options == %{"turn_control" => turn_control}
    end

    assert {:error, _} =
             compile_with_agent_caps(%{
               speech_to_speech: %{
                 provider: "morse",
                 model: "morse",
                 options: %{turn_control: "automatic"}
               }
             })
  end

  test "caller STT may coexist with agent STS without inheriting the agent output slot" do
    assert {:ok, plan} =
             compile_with_agent_caps(
               %{speech_to_speech: %{provider: "morse", model: "morse", options: %{}}},
               %{speech_to_text: %{provider: "morse", model: "morse", options: %{}}}
             )

    assert plan.participants["caller"].capabilities.speech_to_text.provider == "morse"
    assert plan.participants["assistant"].capabilities.output_speech_to_text == nil
  end

  test "existing text-model selection still compiles unchanged" do
    assert {:ok, plan} =
             compile_with_agent_caps(%{
               model_inference: %{provider: "fixture", model: "echo", options: %{}}
             })

    caps = plan.participants["assistant"].capabilities
    assert caps.model_inference.provider == "fixture"
    assert caps.speech_to_speech == nil
    assert caps.output_speech_to_text == nil
  end

  defp compile_with_agent_caps(agent_caps, caller_caps \\ %{}) do
    source = %{
      schema_version: "20260915.01",
      name: "STS selection",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: caller_caps
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          capabilities: agent_caps
        }
      }
    }

    with {:ok, call_spec} <- CallSpec.new(source, resource_id: "sts", revision: 1),
         {:ok, invocation} <-
           CallInvocation.new(
             %{call_spec: %{id: "sts", revision: 1}, transport: %{type: "web"}},
             tenant_id: "tenant-sts",
             actor_id: "operator-sts"
           ) do
      CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    end
  end
end
