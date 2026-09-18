defmodule Vxpipe.CallEngine.CallSpec.CompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec

  alias Vxpipe.CallEngine.CallSpec.{
    CapabilitySelection,
    ConnectionIntent,
    Participant,
    ToolSelection,
    ToolVisibility
  }

  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallSpecCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility, as: ResolvedToolVisibility
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.CurrentTime

  @schema_version "20260915.01"

  test "Elixir and JSON inputs produce the same typed call spec" do
    input = call_spec_input()

    assert {:ok, from_elixir} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert {:ok, from_json} =
             input
             |> JSON.encode!()
             |> CallSpec.from_json(resource_id: "support", revision: 7)

    assert from_elixir == from_json
    assert from_elixir.schema_version == @schema_version
    assert from_elixir.resource_id == "support"
    assert from_elixir.revision == 7
    assert from_elixir.entry_caller == "caller"
    assert from_elixir.entry_receiver == "reception"
    assert from_elixir.tool_visibility == %ToolVisibility{default: :hidden, overrides: %{}}

    assert %Participant{
             kind: :human,
             connection: %ConnectionIntent{
               service: :web,
               mode: :receive,
               admission: :start_call
             }
           } = from_elixir.participants["caller"]

    assert %Participant{
             kind: :agent,
             prompt: "Answer clearly.",
             first_message: :wait_for_input,
             transfers: []
           } = from_elixir.participants["reception"]
  end

  test "rejects invalid entry references with paths before compilation" do
    cases = [
      {Map.delete(call_spec_input(), :entry_caller), ["entry_caller"]},
      {%{call_spec_input() | entry_caller: 12}, ["entry_caller"]},
      {%{call_spec_input() | entry_caller: "missing"}, ["entry_caller"]},
      {%{call_spec_input() | entry_receiver: "caller"}, ["entry_receiver"]}
    ]

    for {input, path} <- cases do
      assert {:error,
              %Error{
                code: :invalid_call_spec,
                message: "The call spec is invalid.",
                details: %{"path" => ^path}
              }} = CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "accepts a human entry receiver without inventing an agent activation" do
    input =
      put_in(call_spec_input(), [:participants, "reception"], %{
        type: "human",
        description: "The receiving person",
        connection: %{
          service: "web",
          mode: "receive",
          admission: "start_call"
        }
      })

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "human-support", revision: 1)

    assert call_spec.participants["reception"].kind == :human

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    invocation = %{
      invocation
      | call_spec_id: "human-support",
        call_spec_revision: 1
    }

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    assert plan.participants["reception"].kind == :human
    assert plan.participants["reception"].activation_id == nil
  end

  test "rejects unsupported schema versions, fields, and participant options" do
    cases = [
      {%{call_spec_input() | schema_version: "20260906.02"}, ["schema_version"]},
      {Map.put(call_spec_input(), :provider_api_key, "do-not-echo-me"), ["provider_api_key"]},
      {put_in(call_spec_input(), [:participants, "caller", :prompt], "wrong kind"),
       ["participants", "caller", "prompt"]},
      {put_in(
         call_spec_input(),
         [:participants, "caller", :connection, :service],
         "bad service"
       ), ["participants", "caller", "connection", "service"]},
      {put_in(
         call_spec_input(),
         [:participants, "reception", :tools, "get_current_time", :type],
         "mcp"
       ), ["participants", "reception", "tools", "get_current_time", "integration"]},
      {put_in(
         call_spec_input(),
         [:participants, "reception", :tools, "get_current_time", :conversation_mode],
         "inline"
       ), ["participants", "reception", "tools", "get_current_time", "conversation_mode"]},
      {put_in(
         call_spec_input(),
         [:participants, "reception", :tools],
         %{"transfer" => %{type: "host", tool: "get_current_time"}}
       ), ["participants", "reception", "tools", "transfer"]},
      {put_in(call_spec_input(), [:participants, "reception", :transfers], ["caller"]),
       ["participants", "reception", "transfers", "0"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_spec, details: details}} =
               CallSpec.new(input, resource_id: "support", revision: 7)

      assert details["path"] == path
      refute inspect(details) =~ "do-not-echo-me"
    end
  end

  test "parses a remote MCP operation under its model-visible local alias" do
    input =
      put_in(
        call_spec_input(),
        [:participants, "reception", :tools],
        %{
          "customer_lookup" => %{
            type: "mcp",
            integration: "records",
            tool: "lookup_customer"
          }
        }
      )

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert %ToolSelection{
             name: "customer_lookup",
             type: :mcp,
             integration: "records",
             tool: "lookup_customer"
           } = call_spec.participants["reception"].tools["customer_lookup"]

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:error,
            %Error{
              code: :call_spec_resolution_failed,
              details: %{
                "path" => ["participants", "reception", "tools", "customer_lookup"]
              }
            }} = CallSpecCompiler.compile(call_spec, invocation, registries())
  end

  test "defaults tool conversation admission to blocking and accepts an explicit non-blocking opt-out" do
    assert {:ok, blocking_call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert %ToolSelection{conversation_mode: :blocking} =
             blocking_call_spec.participants["reception"].tools["get_current_time"]

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, blocking_plan} =
             CallSpecCompiler.compile(blocking_call_spec, invocation, registries())

    assert %ToolBinding{conversation_mode: :blocking} =
             blocking_plan.participants["reception"].tools["get_current_time"]

    non_blocking_input =
      put_in(
        call_spec_input(),
        [:participants, "reception", :tools, "get_current_time", :conversation_mode],
        "non_blocking"
      )

    assert {:ok, non_blocking_call_spec} =
             CallSpec.new(non_blocking_input, resource_id: "support", revision: 7)

    assert %ToolSelection{conversation_mode: :non_blocking} =
             non_blocking_call_spec.participants["reception"].tools["get_current_time"]

    assert {:ok, non_blocking_plan} =
             CallSpecCompiler.compile(non_blocking_call_spec, invocation, registries())

    assert %ToolBinding{conversation_mode: :non_blocking} =
             non_blocking_plan.participants["reception"].tools["get_current_time"]
  end

  test "invocation identity comes from trusted options and entry overrides are rejected" do
    input = %{
      call_spec: %{id: "support", revision: 7},
      transport: %{type: "web"},
      initial_variables: %{}
    }

    assert {:ok, invocation} =
             CallInvocation.new(input,
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: "call-demo",
               room_id: "room-demo"
             )

    assert invocation.tenant_id == "tenant-demo"
    assert invocation.actor_id == "actor-demo"
    assert invocation.call_spec_id == "support"
    assert invocation.call_spec_revision == 7
    assert invocation.transport == :web

    for forbidden <- [:tenant_id, :entry_caller, :entry_receiver, :limits] do
      assert {:error,
              %Error{
                code: :invalid_call_invocation,
                message: "The call invocation is invalid.",
                details: %{"path" => [path]}
              }} =
               CallInvocation.new(Map.put(input, forbidden, "override"),
                 tenant_id: "tenant-demo",
                 actor_id: "actor-demo"
               )

      assert path == Atom.to_string(forbidden)
    end
  end

  test "accepts every URL-safe leading character used by tenant keys" do
    for tenant_id <- ["-tenant-key", "_tenant-key"] do
      assert {:ok, invocation} =
               CallInvocation.new(invocation_input(),
                 tenant_id: tenant_id,
                 actor_id: "actor-demo"
               )

      assert invocation.tenant_id == tenant_id
    end
  end

  test "compiles a pinned plan from inline capabilities and the host-tool registry" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: "call-one",
               room_id: "room-one"
             )

    registries = registries()

    assert {:ok, %ResolvedCallPlan{} = plan} =
             CallSpecCompiler.compile(call_spec, invocation, registries)

    assert plan.call_spec_id == "support"
    assert plan.call_spec_revision == 7
    assert plan.schema_version == @schema_version
    assert plan.tenant_id == "tenant-demo"
    assert plan.call_id == "call-one"
    assert plan.room_id == "room-one"
    assert plan.entry_caller == "caller"
    assert plan.entry_receiver == "reception"
    assert plan.tool_visibility == %ResolvedToolVisibility{default: :hidden, overrides: %{}}

    caller = plan.participants["caller"]
    receiver = plan.participants["reception"]

    assert caller.call_spec_key == "caller"
    assert receiver.call_spec_key == "reception"
    assert caller.participant_id != receiver.participant_id
    assert caller.activation_id == nil
    assert String.starts_with?(receiver.activation_id, "act_")

    assert %CapabilitySelection{
             kind: :speech_to_text,
             provider: "morse",
             model: "morse",
             options: %{}
           } = caller.capabilities.speech_to_text

    assert receiver.capabilities.speech_to_text == nil

    assert %CapabilitySelection{
             kind: :model_inference,
             provider: "fixture",
             model: "careful",
             options: %{}
           } = receiver.capabilities.model_inference

    assert %ToolBinding{
             name: "get_current_time",
             action: CurrentTime,
             type: :host
           } = receiver.tools["get_current_time"]

    changed =
      put_in(
        call_spec_input(),
        [:participants, "reception", :capabilities, :model_inference, :model],
        "changed"
      )

    assert changed.participants["reception"].capabilities.model_inference.model == "changed"
    assert receiver.capabilities.model_inference.model == "careful"
  end

  test "resolves and pins call spec, tenant, application, and platform duration precedence" do
    omitted_input = Map.delete(call_spec_input(), :limits)

    assert {:ok, omitted_call_spec} =
             CallSpec.new(omitted_input, resource_id: "support", revision: 7)

    assert omitted_call_spec.max_duration_ms == nil

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: "call-duration",
               room_id: "room-duration"
             )

    assert {:ok, tenant_plan} =
             CallSpecCompiler.compile(omitted_call_spec, invocation, registries(),
               duration_limits: [tenant: 90_000, application: 120_000]
             )

    assert tenant_plan.max_duration_ms == 90_000

    assert {:ok, application_plan} =
             CallSpecCompiler.compile(omitted_call_spec, invocation, registries(),
               duration_limits: [application: 120_000]
             )

    assert application_plan.max_duration_ms == 120_000

    assert {:ok, platform_plan} =
             CallSpecCompiler.compile(omitted_call_spec, invocation, registries())

    assert platform_plan.max_duration_ms == 1_800_000

    assert {:ok, explicit_call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert {:ok, explicit_plan} =
             CallSpecCompiler.compile(explicit_call_spec, invocation, registries(),
               duration_limits: [tenant: 90_000, application: 120_000]
             )

    assert explicit_plan.max_duration_ms == 1_800_000
  end

  test "validates and resolves participant-local tool visibility overrides" do
    reception = get_in(call_spec_input(), [:participants, "reception"])

    input =
      call_spec_input()
      |> Map.put(:tool_visibility, "full")
      |> Map.put(:tool_visibility_overrides, %{
        "reception" => %{"get_current_time" => "metadata"},
        "billing" => %{"get_current_time" => "hidden"}
      })
      |> put_in([:participants, "billing"], reception)

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "support", revision: 7)

    assert call_spec.tool_visibility == %ToolVisibility{
             default: :full,
             overrides: %{
               "reception" => %{"get_current_time" => :metadata},
               "billing" => %{"get_current_time" => :hidden}
             }
           }

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())

    reception_id = plan.participants["reception"].participant_id
    billing_id = plan.participants["billing"].participant_id

    assert %ResolvedToolVisibility{default: :full, overrides: overrides} =
             plan.tool_visibility

    assert overrides == %{
             reception_id => %{"get_current_time" => :metadata},
             billing_id => %{"get_current_time" => :hidden}
           }
  end

  test "rejects invalid tool visibility policies with precise paths" do
    cases = [
      {Map.put(call_spec_input(), :tool_visibility, "verbose"), ["tool_visibility"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, []), ["tool_visibility_overrides"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, %{"missing" => %{}}),
       ["tool_visibility_overrides", "missing"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, %{"caller" => %{}}),
       ["tool_visibility_overrides", "caller"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, %{"reception" => []}),
       ["tool_visibility_overrides", "reception"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, %{
         "reception" => %{"missing" => "full"}
       }), ["tool_visibility_overrides", "reception", "missing"]},
      {Map.put(call_spec_input(), :tool_visibility_overrides, %{
         "reception" => %{"get_current_time" => "verbose"}
       }), ["tool_visibility_overrides", "reception", "get_current_time"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_spec, details: %{"path" => ^path}}} =
               CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "creates fresh runtime participant and activation identities for every call" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert {:ok, first_invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, second_invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, first} = CallSpecCompiler.compile(call_spec, first_invocation, registries())
    assert {:ok, second} = CallSpecCompiler.compile(call_spec, second_invocation, registries())

    refute first.call_id == second.call_id
    refute first.room_id == second.room_id

    refute first.participants["caller"].participant_id ==
             second.participants["caller"].participant_id

    refute first.participants["reception"].activation_id ==
             second.participants["reception"].activation_id
  end

  test "fails safely when a tool is unavailable or aliases do not match" do
    cases = [
      {put_in(
         call_spec_input(),
         [:participants, "reception", :tools],
         %{"clock" => %{type: "host", tool: "get_current_time"}}
       ), registries(), ["participants", "reception", "tools", "clock"]},
      {call_spec_input(), put_in(registries(), [:host_tools], %{}),
       ["participants", "reception", "tools", "get_current_time"]}
    ]

    for {input, registry, path} <- cases do
      assert {:ok, call_spec} =
               CallSpec.new(input, resource_id: "support", revision: 7)

      assert {:ok, invocation} =
               CallInvocation.new(invocation_input(),
                 tenant_id: "tenant-demo",
                 actor_id: "actor-demo"
               )

      assert {:error, %Error{code: :call_spec_resolution_failed, details: details}} =
               CallSpecCompiler.compile(call_spec, invocation, registry)

      assert details["path"] == path
    end
  end

  defp call_spec_input do
    %{
      schema_version: @schema_version,
      name: "Customer support",
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          speech_to_text: %{provider: "morse", model: "morse"},
          model_inference: %{provider: "fixture", model: "default"},
          text_to_speech: %{provider: "morse", model: "morse"}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          description: "The caller",
          connection: %{
            service: "web",
            mode: "receive",
            admission: "start_call"
          }
        },
        "reception" => %{
          type: "agent",
          description: "The receiving agent",
          prompt: "Answer clearly.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "careful"}},
          tools: %{
            "get_current_time" => %{type: "host", tool: "get_current_time"}
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 1_800_000}
    }
  end

  defp invocation_input do
    %{
      call_spec: %{id: "support", revision: 7},
      initial_variables: %{},
      transport: %{type: "web"}
    }
  end

  defp registries do
    %{
      host_tools: %{"get_current_time" => CurrentTime}
    }
  end
end
