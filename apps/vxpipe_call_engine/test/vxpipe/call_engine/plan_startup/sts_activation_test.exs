defmodule Vxpipe.CallEngine.PlanStartup.STSActivationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, PlanStartup}
  alias Vxpipe.Providers.MorseCode.{STSSession, STTSession}

  test "morse STS resolves an agent runtime without a text model" do
    plan =
      compile_plan(%{
        speech_to_speech: %{provider: "morse", model: "morse", options: %{}}
      })

    assert {:ok, startup} = PlanStartup.new(plan, options())
    assert startup.agent_activation == nil
    assert startup.text_to_speech == nil
    assert {STSSession, public} = startup.speech_to_speech.provider
    assert public[:turn_control] in [nil, "provider"]
    assert startup.speech_to_speech.output_speech_to_text == nil
    refute inspect(startup) =~ "private-marker"
  end

  test "STS without output transcription resolves its agent output STT" do
    plan =
      compile_plan(%{
        speech_to_speech: %{
          provider: "morse",
          model: "morse",
          options: %{output_transcript: false}
        },
        output_speech_to_text: %{provider: "morse", model: "morse", options: %{}}
      })

    assert :ok = PlanStartup.validate(plan, options())
    assert {:ok, startup} = PlanStartup.new(plan, options())
    assert startup.agent_activation == nil
    assert {STSSession, _public} = startup.speech_to_speech.provider
    assert {STTSession, _stt_public} = startup.speech_to_speech.output_speech_to_text
  end

  test "agent-output recognition still requires its STT provider to be enabled" do
    plan =
      compile_plan(%{
        speech_to_speech: %{
          provider: "morse",
          model: "morse",
          options: %{output_transcript: false}
        },
        output_speech_to_text: %{provider: "morse", model: "morse", options: %{}}
      })

    for registry <- [%{}, %{STTSession => [enabled: false]}] do
      settings = Keyword.put(options(), :speech_to_text, providers: registry)
      assert {:error, error} = PlanStartup.validate(plan, settings)
      assert error.code == :unsupported_call_plan

      assert error.details["path"] == [
               "participants",
               "assistant",
               "capabilities",
               "output_speech_to_text"
             ]
    end
  end

  defp compile_plan(agent_caps) do
    source = %{
      schema_version: "20260915.01",
      name: "STS activation",
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
           ),
         {:ok, plan} <- CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}}) do
      plan
    else
      {:error, error} -> flunk("plan failed: #{inspect(error)}")
    end
  end

  defp options do
    [
      speech_to_text: [
        providers: %{
          Vxpipe.CallEngine.Provider.MorseCodeSTT.Session => [enabled: true, media_ingress: []],
          Vxpipe.Providers.MorseCode.STTSession => [enabled: true, media_ingress: []]
        }
      ],
      text_to_speech: [
        providers: %{}
      ],
      speech_to_speech: [
        providers: %{
          STSSession => [enabled: true]
        }
      ]
    ]
  end
end
