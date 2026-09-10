defmodule Vxpipe.CallEngine.CallDefinition.AgentTransferCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.AgentRuntime.ToolRegistry
  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.InvocationBinding
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

  test "derives one default-blocking transfer tool from an agent allowlist" do
    assert {:ok, definition} =
             transfer_definition()
             |> CallDefinition.new(resource_id: "support", revision: 7)

    assert definition.participants["reception"].transfers == ["billing"]

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation(), registries())

    reception = plan.participants["reception"]
    billing = plan.participants["billing"]

    assert %ToolBinding{
             name: "transfer",
             type: :participant_transfer,
             conversation_mode: :blocking,
             transfer: %Binding{} = binding
           } = reception.tools["transfer"]

    assert binding.source_definition_key == "reception"
    assert binding.source_participant_id == reception.participant_id
    assert binding.source_activation_id == reception.activation_id

    assert %{
             "billing" => %{
               definition_key: "billing",
               participant_id: billing.participant_id,
               description: "A billing specialist"
             }
           } == binding.targets

    assert {:ok, descriptors} = ToolDescriptors.compile(reception.tools)
    assert [%ToolDescriptor{} = descriptor] = descriptors
    assert descriptor.name == "transfer"
    assert descriptor.description == "Transfer the caller to one permitted agent participant."

    assert descriptor.input_schema == %{
             "type" => "object",
             "properties" => %{
               "destination" => %{
                 "type" => "string",
                 "oneOf" => [
                   %{
                     "const" => "billing",
                     "description" => "A billing specialist"
                   }
                 ]
               }
             },
             "required" => ["destination"],
             "additionalProperties" => false
           }

    assert %InvocationBinding{
             name: "transfer",
             conversation_mode: :blocking,
             handler: {:participant_transfer, ^binding}
           } = descriptor.binding

    assert {:ok, registry} = ToolRegistry.new(descriptors)

    assert {:ok, ^descriptor} =
             ToolRegistry.resolve(registry, "transfer", %{"destination" => "billing"})

    assert {:error, :invalid_arguments} =
             ToolRegistry.resolve(registry, "transfer", %{"destination" => "caller"})

    refute inspect(descriptor) =~ reception.participant_id
    refute inspect(descriptor) =~ billing.participant_id
  end

  test "an empty transfer list exposes no generated tool" do
    input = put_in(transfer_definition(), [:participants, "reception", :transfers], [])

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation(), registries())

    assert plan.participants["reception"].tools == %{}
    assert {:ok, []} = ToolDescriptors.compile(plan.participants["reception"].tools)
  end

  test "a generated transfer tool accepts the ordinary participant-local visibility override" do
    input =
      Map.put(transfer_definition(), :tool_visibility_overrides, %{
        "reception" => %{"transfer" => "metadata"}
      })

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation(), registries())

    reception = plan.participants["reception"]
    assert plan.tool_visibility.overrides[reception.participant_id] == %{"transfer" => :metadata}
  end

  test "rejects malformed, duplicate, missing, self, and non-agent destinations" do
    cases = [
      {[12], ["participants", "reception", "transfers", "0"]},
      {["billing", "billing"], ["participants", "reception", "transfers", "1"]},
      {["missing"], ["participants", "reception", "transfers", "0"]},
      {["reception"], ["participants", "reception", "transfers", "0"]},
      {["caller"], ["participants", "reception", "transfers", "0"]}
    ]

    for {transfers, path} <- cases do
      input = put_in(transfer_definition(), [:participants, "reception", :transfers], transfers)

      assert {:error,
              %Error{
                code: :invalid_call_definition,
                message: "The call definition is invalid.",
                details: %{"path" => ^path}
              }} = CallDefinition.new(input, resource_id: "support", revision: 7)
    end
  end

  defp transfer_definition do
    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          model_inference: "default-model",
          text_to_speech: "default-voice"
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          prompt: "Route the caller safely.",
          tools: %{},
          transfers: ["billing"]
        },
        "billing" => %{
          type: "agent",
          description: "A billing specialist",
          prompt: "Help with billing.",
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp invocation do
    {:ok, invocation} =
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
        "default-model" => %{
          kind: :model_inference,
          provider: :test_model,
          options: %{model: "default"}
        },
        "default-voice" => %{
          kind: :text_to_speech,
          provider: :test_tts,
          options: %{voice: "default"}
        }
      },
      host_tools: %{}
    }
  end
end
