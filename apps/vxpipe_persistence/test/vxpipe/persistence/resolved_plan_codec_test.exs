defmodule Vxpipe.Persistence.ResolvedPlanCodecTest do
  use ExUnit.Case, async: true

  test "normalizes legacy call definition plan fields and structs" do
    legacy = %{
      __struct__: Vxpipe.CallEngine.ResolvedCallPlan,
      definition_id: "legacy-call-definition",
      definition_revision: 3,
      schema_version: "20260915.01",
      tenant_id: "tenant",
      actor_id: "actor",
      call_id: "call",
      room_id: "room",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "agent",
      opening_audio: nil,
      wait_sounds: %{
        __struct__: Vxpipe.CallEngine.CallDefinition.WaitSounds
      },
      media_policy: %{
        __struct__: Vxpipe.CallEngine.CallDefinition.MediaPolicy
      },
      participants: %{
        "caller" => %{
          __struct__: Vxpipe.CallEngine.ResolvedCallPlan.Participant,
          definition_key: "caller",
          telephony_service: %{
            __struct__: Vxpipe.CallEngine.Telephony.ServiceReference,
            tenant_id: "tenant",
            service_id: "service",
            name: "phone",
            provider: "telnyx",
            provider_connection_id: "application",
            credential_id: "credential"
          },
          tools: %{
            "transfer" => %{
              __struct__: Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding,
              transfer: %{
                __struct__: Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding,
                source_definition_key: "caller",
                targets: %{
                  "agent" => %{
                    definition_key: "agent",
                    participant_id: "participant",
                    description: nil,
                    reason_required: false
                  }
                }
              }
            }
          }
        }
      },
      transfer_policy: %{
        __struct__: Vxpipe.CallEngine.CallDefinition.TransferPolicy
      },
      call_variables: %{
        __struct__: Vxpipe.CallEngine.ResolvedCallPlan.CallVariables,
        sections: %{
          "user_payload" => %{
            "definition_id" => "must-stay-definition-id",
            "definition_key" => "must-stay-definition-key"
          }
        }
      },
      tool_visibility: %{
        __struct__: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
      },
      max_duration_ms: 1_000
    }

    assert {:ok, plan} =
             legacy
             |> :erlang.term_to_binary([:deterministic])
             |> Vxpipe.Persistence.ResolvedPlanCodec.decode()

    assert plan.call_spec_id == "legacy-call-definition"
    assert plan.call_spec_revision == 3
    assert plan.credential_bindings == nil
    assert plan.wait_sounds.__struct__ == Vxpipe.CallEngine.CallSpec.WaitSounds
    assert plan.transfer_policy.__struct__ == Vxpipe.CallEngine.CallSpec.TransferPolicy
    caller = Map.fetch!(plan.participants, "caller")
    assert caller.telephony_service.credential_owner == nil
    assert caller.telephony_service.credential_name == nil
    assert caller.telephony_service.credential_id == "credential"
    transfer = Map.fetch!(caller.tools, "transfer").transfer
    assert transfer.source_call_spec_key == "caller"
    assert Map.fetch!(transfer.targets, "agent").call_spec_key == "agent"

    assert plan.call_variables.sections["user_payload"] == %{
             "definition_id" => "must-stay-definition-id",
             "definition_key" => "must-stay-definition-key"
           }
  end

  test "normalizes capability selections predating speech-to-speech" do
    old_resolved = %{
      __struct__: Vxpipe.CallEngine.ResolvedCallPlan.Capabilities,
      speech_to_text: nil,
      model_inference: nil,
      text_to_speech: nil
    }

    old_spec = %{
      __struct__: Vxpipe.CallEngine.CallSpec.Capabilities,
      speech_to_text: nil,
      model_inference: nil,
      text_to_speech: nil
    }

    for old <- [old_resolved, old_spec] do
      assert {:ok, plan} =
               legacy_plan(old)
               |> :erlang.term_to_binary([:deterministic])
               |> Vxpipe.Persistence.ResolvedPlanCodec.decode()

      caller = Map.fetch!(plan.participants, "caller")
      assert caller.capabilities.speech_to_speech == nil
      assert caller.capabilities.output_speech_to_text == nil
    end
  end

  defp legacy_plan(capabilities) do
    %{
      __struct__: Vxpipe.CallEngine.ResolvedCallPlan,
      definition_id: "legacy-capabilities",
      definition_revision: 1,
      schema_version: "20260915.01",
      tenant_id: "tenant",
      actor_id: "actor",
      call_id: "call",
      room_id: "room",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "caller",
      opening_audio: nil,
      participants: %{
        "caller" => %{
          __struct__: Vxpipe.CallEngine.ResolvedCallPlan.Participant,
          definition_key: "caller",
          capabilities: capabilities
        }
      }
    }
  end
end
