defmodule Vxpipe.CallEngine.CallDefinition.MediaPolicyCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallDefinition.MediaPolicy
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy, as: ResolvedMediaPolicy

  @schema_version "20260915.01"

  test "preserves omitted fields and explicit empty route maps" do
    input =
      definition_input()
      |> Map.put(:media_policy, %{audio_routes: %{}})
      |> put_in(
        [:participants, "specialist", :while_present],
        %{transcript_routes: %{}, record_audio: false}
      )

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 8)

    assert {:ok, ^definition} =
             input
             |> JSON.encode!()
             |> CallDefinition.from_json(resource_id: "support", revision: 8)

    assert %MediaPolicy{
             audio_routes: %{},
             transcript_routes: :inherit,
             record_audio: :inherit,
             save_transcripts: :inherit
           } = definition.media_policy

    assert %MediaPolicy{
             audio_routes: :inherit,
             transcript_routes: %{},
             record_audio: false,
             save_transcripts: :inherit
           } = definition.participants["specialist"].while_present

    assert %MediaPolicy{
             audio_routes: :inherit,
             transcript_routes: :inherit,
             record_audio: :inherit,
             save_transcripts: :inherit
           } = definition.participants["caller"].while_present
  end

  test "compiles direct definition-key routes to immutable runtime participant identities" do
    input =
      definition_input()
      |> Map.put(:media_policy, %{
        audio_routes: %{
          "caller" => ["reception"],
          "reception" => ["caller"]
        },
        transcript_routes: %{
          "caller" => ["caller", "reception"]
        },
        record_audio: true,
        save_transcripts: true
      })
      |> put_in(
        [:participants, "specialist", :while_present],
        %{
          audio_routes: %{
            "caller" => ["specialist"],
            "specialist" => ["caller"]
          },
          transcript_routes: %{
            "caller" => ["caller", "specialist"],
            "specialist" => ["caller", "specialist"]
          },
          record_audio: false,
          save_transcripts: false
        }
      )

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 8)

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())

    caller_id = plan.participants["caller"].participant_id
    reception_id = plan.participants["reception"].participant_id
    specialist_id = plan.participants["specialist"].participant_id

    assert %ResolvedMediaPolicy{
             audio_routes: audio_routes,
             transcript_routes: transcript_routes,
             record_audio: true,
             save_transcripts: true
           } = plan.media_policy

    assert audio_routes == %{
             caller_id => MapSet.new([reception_id]),
             reception_id => MapSet.new([caller_id])
           }

    assert transcript_routes == %{
             caller_id => MapSet.new([caller_id, reception_id])
           }

    assert %ResolvedMediaPolicy{
             audio_routes: specialist_audio_routes,
             transcript_routes: specialist_transcript_routes,
             record_audio: false,
             save_transcripts: false
           } = plan.participants["specialist"].while_present

    assert specialist_audio_routes == %{
             caller_id => MapSet.new([specialist_id]),
             specialist_id => MapSet.new([caller_id])
           }

    assert specialist_transcript_routes == %{
             caller_id => MapSet.new([caller_id, specialist_id]),
             specialist_id => MapSet.new([caller_id, specialist_id])
           }
  end

  test "rejects malformed policies and unknown participant references at their exact paths" do
    cases = [
      {Map.put(definition_input(), :media_policy, nil), ["media_policy"]},
      {Map.put(definition_input(), :media_policy, %{unknown: true}), ["media_policy", "unknown"]},
      {Map.put(definition_input(), :media_policy, %{audio_routes: []}),
       ["media_policy", "audio_routes"]},
      {Map.put(definition_input(), :media_policy, %{audio_routes: %{"caller" => "reception"}}),
       ["media_policy", "audio_routes", "caller"]},
      {Map.put(definition_input(), :media_policy, %{
         audio_routes: %{"caller" => ["reception", "reception"]}
       }), ["media_policy", "audio_routes", "caller", "1"]},
      {Map.put(definition_input(), :media_policy, %{audio_routes: %{"missing" => []}}),
       ["media_policy", "audio_routes", "missing"]},
      {Map.put(definition_input(), :media_policy, %{
         transcript_routes: %{"caller" => ["missing"]}
       }), ["media_policy", "transcript_routes", "caller", "0"]},
      {Map.put(definition_input(), :media_policy, %{record_audio: "false"}),
       ["media_policy", "record_audio"]},
      {put_in(
         definition_input(),
         [:participants, "specialist", :while_present],
         %{save_transcripts: 0}
       ), ["participants", "specialist", "while_present", "save_transcripts"]}
    ]

    for {input, path} <- cases do
      assert {:error,
              %Error{
                code: :invalid_call_definition,
                details: %{"path" => ^path}
              }} = CallDefinition.new(input, resource_id: "support", revision: 8)
    end
  end

  test "compiler rejects a forged media policy instead of trusting constructed structs" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 8)

    forged_policy = %{definition.media_policy | record_audio: :enabled}
    forged_definition = %{definition | media_policy: forged_policy}

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:error,
            %Error{
              code: :call_definition_resolution_failed,
              details: %{"path" => ["media_policy"]}
            }} = DefinitionCompiler.compile(forged_definition, invocation, registries())
  end

  defp definition_input do
    %{
      schema_version: @schema_version,
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "test:scripted"}
        }
      },
      participants: %{
        "caller" => human_participant(),
        "reception" => %{
          type: "agent",
          prompt: "Answer clearly."
        },
        "specialist" => human_participant()
      }
    }
  end

  defp human_participant do
    %{
      type: "human",
      connection: %{
        service: "web",
        mode: "receive",
        admission: "start_call"
      }
    }
  end

  defp invocation_input do
    %{
      call_definition: %{id: "support", revision: 8},
      initial_variables: %{},
      transport: %{type: "web"}
    }
  end

  defp registries do
    %{
      host_tools: %{}
    }
  end
end
