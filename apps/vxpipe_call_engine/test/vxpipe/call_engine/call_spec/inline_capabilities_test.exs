defmodule Vxpipe.CallEngine.CallSpec.InlineCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}

  test "compiles actual providers and whole-selection overrides without a profile registry" do
    source = source()

    assert {:ok, call_spec} = CallSpec.new(source, resource_id: "inline", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "inline", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-inline",
               actor_id: "operator-inline"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    selection = plan.participants["assistant"].capabilities.model_inference
    assert selection.provider == "google"
    assert selection.model == "gemini-2.5-flash"
    assert selection.credential_name == "default"
    assert selection.options == %{"temperature" => 0.2}
    refute Map.has_key?(Map.from_struct(selection), :profile)
    assert plan.participants["caller"].capabilities.speech_to_text.provider == "deepgram"
    assert plan.opening_audio.text_to_speech.provider == "morse"

    overridden =
      put_in(source, [:participants, "assistant", :capabilities], %{
        model_inference: %{provider: "fixture", model: "echo", options: %{}}
      })

    assert {:ok, call_spec} = CallSpec.new(overridden, resource_id: "inline", revision: 1)
    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    selection = plan.participants["assistant"].capabilities.model_inference
    assert selection.provider == "fixture"
    assert selection.options == %{}
    assert selection.credential_name == nil
  end

  test "rejects profile strings, internal adapters and credential or transport option injection" do
    path = ["defaults", "capabilities", "model_inference"]

    for selection <- [
          "old-google-profile",
          %{provider: "req_llm", model: "google:gemini-2.5-flash"},
          %{provider: "google", model: "google:gemini-2.5-flash"},
          %{provider: "google", model: "gemini-2.5-flash", credential_name: "../other"},
          %{provider: "google", model: "gemini-2.5-flash", options: %{api_key: "private-marker"}},
          %{provider: "google", model: "gemini-2.5-flash", options: %{temperature: "warm"}},
          %{
            provider: "google",
            model: "gemini-2.5-flash",
            provider_options: %{base_url: "https://private-marker.example.test"}
          }
        ] do
      input = put_in(source(), [:defaults, :capabilities, :model_inference], selection)
      assert {:error, error} = CallSpec.new(input, resource_id: "inline", revision: 1)
      assert Enum.take(error.details["path"], 3) == path
      refute inspect(error) =~ "private-marker"
    end
  end

  test "validates provider option conflicts and speech format before compilation" do
    input =
      put_in(source(), [:defaults, :capabilities, :model_inference, :provider_options], %{
        google_thinking_budget: 1024,
        google_thinking_level: "high"
      })

    assert {:error, _} = CallSpec.new(input, resource_id: "inline", revision: 1)

    input =
      put_in(source(), [:defaults, :capabilities, :speech_to_text, :options, :encoding], "mp3")

    assert {:error, _} = CallSpec.new(input, resource_id: "inline", revision: 1)
  end

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Inline tenant voice",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{
          speech_to_text: %{
            provider: "deepgram",
            model: "flux-general-en",
            options: %{encoding: "opus", sample_rate: 48_000}
          },
          model_inference: %{
            provider: "google",
            model: "gemini-2.5-flash",
            options: %{temperature: 0.2}
          }
        }
      },
      opening_audio: %{
        type: "text",
        text: "E",
        text_to_speech: %{provider: "morse", model: "morse", options: %{sample_rate: 48_000}}
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
