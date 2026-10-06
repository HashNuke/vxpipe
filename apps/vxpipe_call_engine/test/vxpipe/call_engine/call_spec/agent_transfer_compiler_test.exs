defmodule Vxpipe.CallEngine.CallSpec.AgentTransferCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.AgentRuntime.ToolRegistry
  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallSpecCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.Tool.InvocationBinding
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

  test "derives one default-blocking transfer tool from an agent allowlist" do
    assert {:ok, call_spec} =
             transfer_call_spec()
             |> CallSpec.new(resource_id: "support", revision: 7)

    assert call_spec.participants["reception"].transfers == ["billing"]

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    reception = plan.participants["reception"]
    billing = plan.participants["billing"]

    assert %ToolBinding{
             name: "transfer",
             type: :participant_transfer,
             conversation_mode: :blocking,
             transfer: %Binding{} = binding
           } = reception.tools["transfer"]

    assert binding.source_call_spec_key == "reception"
    assert binding.source_participant_id == reception.participant_id
    assert binding.source_activation_id == reception.activation_id

    assert %{
             "billing" => %{
               call_spec_key: "billing",
               participant_id: billing.participant_id,
               description: "A billing specialist",
               reason_required: false
             }
           } == binding.targets

    assert {:ok, descriptors} = ToolDescriptors.compile(reception.tools)
    assert [%ToolDescriptor{} = descriptor] = descriptors
    assert descriptor.name == "transfer"
    assert descriptor.description == "Transfer the caller to one permitted participant."

    assert descriptor.input_schema == %{
             "type" => "object",
             "properties" => %{
               "destination" => %{
                 "type" => "string",
                 "enum" => ["billing"],
                 "description" => "Permitted destination: billing (A billing specialist)."
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
    input = put_in(transfer_call_spec(), [:participants, "reception", :transfers], [])

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    assert plan.participants["reception"].tools == %{}
    assert {:ok, []} = ToolDescriptors.compile(plan.participants["reception"].tools)
  end

  test "rejects an authored tool that collides with the generated transfer alias" do
    input =
      put_in(
        transfer_call_spec(),
        [:participants, "reception", :tools],
        %{"transfer" => %{type: "platform", tool: "hangup"}}
      )

    assert {:error,
            %Error{
              code: :invalid_call_spec,
              details: %{"path" => ["participants", "reception", "tools", "transfer"]}
            }} = CallSpec.new(input, resource_id: "support", revision: 7)
  end

  test "pins a call-level total transfer attempt timeout" do
    assert {:ok, default_call_spec} =
             transfer_call_spec()
             |> CallSpec.new(resource_id: "support", revision: 7)

    assert default_call_spec.transfer_policy.attempt_timeout_ms == 30_000

    input = Map.put(transfer_call_spec(), :transfer_policy, %{attempt_timeout_ms: 12_000})

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert call_spec.transfer_policy.attempt_timeout_ms == 12_000

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    assert plan.transfer_policy.attempt_timeout_ms == 12_000

    for invalid <- [0, 999, 120_001, "30000"] do
      input = Map.put(transfer_call_spec(), :transfer_policy, %{attempt_timeout_ms: invalid})

      assert {:error,
              %Error{
                code: :invalid_call_spec,
                details: %{
                  "path" => ["transfer_policy", "attempt_timeout_ms"]
                }
              }} = CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "pins each destination agent's inbound transfer history policy" do
    assert {:ok, default_call_spec} =
             transfer_call_spec()
             |> CallSpec.new(resource_id: "support", revision: 7)

    assert default_call_spec.participants["billing"].transfer_history.mode == :fresh
    assert default_call_spec.participants["billing"].transfer_history.turns == nil

    cases = [
      {%{mode: "fresh"}, %{mode: :fresh, turns: nil}},
      {%{mode: "all_spoken"}, %{mode: :all_spoken, turns: nil}},
      {%{mode: "last_n_spoken", turns: 6}, %{mode: :last_n_spoken, turns: 6}},
      {%{mode: "selected"}, %{mode: :selected, turns: nil}}
    ]

    for {authored, expected} <- cases do
      input =
        put_in(transfer_call_spec(), [:participants, "billing", :transfer_history], authored)

      assert {:ok, call_spec} =
               CallSpec.new(input, resource_id: "support", revision: 7)

      assert Map.take(call_spec.participants["billing"].transfer_history, [:mode, :turns]) ==
               expected

      assert {:ok, plan} =
               CallSpecCompiler.compile(call_spec, invocation(), registries())

      assert Map.take(plan.participants["billing"].transfer_history, [:mode, :turns]) == expected
    end
  end

  test "requires an explicit bounded reason only for selected-history destinations" do
    input =
      put_in(
        transfer_call_spec(),
        [:participants, "billing", :transfer_history],
        %{mode: "selected"}
      )

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    reception = plan.participants["reception"]
    assert {:ok, [descriptor]} = ToolDescriptors.compile(reception.tools)

    assert descriptor.input_schema == %{
             "type" => "object",
             "properties" => %{
               "destination" => %{
                 "type" => "string",
                 "enum" => ["billing"],
                 "description" => "Permitted destination: billing (A billing specialist)."
               },
               "reason" => %{
                 "type" => "string",
                 "minLength" => 1,
                 "maxLength" => 1_024,
                 "description" =>
                   "Required for destination billing. Explain why the caller is being transferred."
               }
             },
             "required" => ["destination", "reason"],
             "additionalProperties" => false
           }

    assert {:ok, registry} = ToolRegistry.new([descriptor])

    assert {:ok, ^descriptor} =
             ToolRegistry.resolve(registry, "transfer", %{
               "destination" => "billing",
               "reason" => "The caller needs help understanding invoice 17."
             })

    assert {:error, :invalid_arguments} =
             ToolRegistry.resolve(registry, "transfer", %{"destination" => "billing"})
  end

  test "pins a web human transfer destination and requires a private briefing reason" do
    input =
      transfer_call_spec()
      |> put_in([:participants, "reception", :transfers], ["human-support"])
      |> put_in(
        [:participants, "human-support"],
        %{
          type: "human",
          description: "A human support specialist",
          connection: %{service: "web", mode: "receive", admission: "transfer"},
          transfer_notice: "This call is recorded."
        }
      )

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert call_spec.participants["human-support"].connection.admission == :transfer
    assert call_spec.participants["human-support"].transfer_notice == "This call is recorded."

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    reception = plan.participants["reception"]
    support = plan.participants["human-support"]
    assert support.connection.admission == :transfer
    assert support.transfer_notice == "This call is recorded."

    assert %{reason_required: true, participant_id: support_participant_id} =
             reception.tools["transfer"].transfer.targets["human-support"]

    assert support_participant_id == support.participant_id

    assert {:ok, [descriptor]} = ToolDescriptors.compile(reception.tools)
    assert {:ok, registry} = ToolRegistry.new([descriptor])

    assert {:error, :invalid_arguments} =
             ToolRegistry.resolve(registry, "transfer", %{"destination" => "human-support"})

    assert {:ok, ^descriptor} =
             ToolRegistry.resolve(registry, "transfer", %{
               "destination" => "human-support",
               "reason" => "Taylor is calling about order 17."
             })
  end

  test "projects mixed transfer argument requirements without provider combinators" do
    input =
      transfer_call_spec()
      |> put_in(
        [:participants, "reception", :transfers],
        ["billing", "human-support"]
      )
      |> put_in(
        [:participants, "human-support"],
        %{
          type: "human",
          description: "A human support specialist",
          connection: %{service: "web", mode: "receive", admission: "transfer"},
          transfer_notice: "This call is recorded."
        }
      )

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

    assert {:ok, [descriptor]} =
             plan.participants["reception"].tools
             |> ToolDescriptors.compile()

    assert descriptor.input_schema == %{
             "type" => "object",
             "properties" => %{
               "destination" => %{
                 "type" => "string",
                 "enum" => ["billing", "human-support"],
                 "description" =>
                   "Permitted destinations: billing (A billing specialist), human-support (A human support specialist)."
               },
               "reason" => %{
                 "type" => "string",
                 "minLength" => 1,
                 "maxLength" => 1_024,
                 "description" =>
                   "Required for destination human-support. Explain why the caller is being transferred."
               }
             },
             "required" => ["destination"],
             "additionalProperties" => false
           }
  end

  test "rejects a human transfer target whose connection is an entry admission" do
    input =
      transfer_call_spec()
      |> put_in([:participants, "reception", :transfers], ["human-support"])
      |> put_in(
        [:participants, "human-support"],
        %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        }
      )

    assert {:error,
            %Error{
              code: :invalid_call_spec,
              details: %{
                "path" => ["participants", "reception", "transfers", "0"]
              }
            }} = CallSpec.new(input, resource_id: "support", revision: 7)
  end

  test "rejects malformed destination transfer history policies at their exact path" do
    cases = [
      {%{mode: "last_n_spoken"}, ["participants", "billing", "transfer_history", "turns"]},
      {%{mode: "last_n_spoken", turns: 0},
       ["participants", "billing", "transfer_history", "turns"]},
      {%{mode: "fresh", turns: 4}, ["participants", "billing", "transfer_history", "turns"]},
      {%{mode: "everything"}, ["participants", "billing", "transfer_history", "mode"]}
    ]

    for {authored, path} <- cases do
      input =
        put_in(transfer_call_spec(), [:participants, "billing", :transfer_history], authored)

      assert {:error,
              %Error{
                code: :invalid_call_spec,
                details: %{"path" => ^path}
              }} = CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "the supervised invocation timeout encloses the total transfer budget" do
    input =
      transfer_call_spec()
      |> put_in([:defaults, :capabilities], %{
        model_inference: %{provider: "fixture", model: "default"}
      })
      |> Map.put(:transfer_policy, %{attempt_timeout_ms: 120_000})

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation(), registries())

    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:fixture, {TestAgentRuntimeModelProvider, [owner: self()]})
      |> Keyword.put(:tool_invocation_timeout_ms, 30_000)

    assert {:ok, startup} =
             PlanStartup.new(plan,
               owner: self(),
               agent_runtime: agent_runtime,
               agent_request_options: [],
               speech_to_text: [providers: %{}],
               text_to_speech: [providers: %{}]
             )

    assert startup.agent_activation[:tool_invocation_timeout_ms] == 121_000
  end

  test "a generated transfer tool accepts the ordinary participant-local visibility override" do
    input =
      Map.put(transfer_call_spec(), :tool_visibility_overrides, %{
        "reception" => %{"transfer" => "metadata"}
      })

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation(), registries())

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
      input = put_in(transfer_call_spec(), [:participants, "reception", :transfers], transfers)

      assert {:error,
              %Error{
                code: :invalid_call_spec,
                message: "The call spec is invalid.",
                details: %{"path" => ^path}
              }} = CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  defp transfer_call_spec do
    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "default"},
          text_to_speech: %{provider: "morse", model: "morse"}
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
