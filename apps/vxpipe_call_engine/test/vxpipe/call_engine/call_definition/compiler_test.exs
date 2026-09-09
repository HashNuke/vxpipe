defmodule Vxpipe.CallEngine.CallDefinition.CompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition

  alias Vxpipe.CallEngine.CallDefinition.{
    CapabilitySelection,
    ConnectionIntent,
    Participant,
    ToolVisibility
  }

  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility, as: ResolvedToolVisibility
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.CurrentTime

  @schema_version "20260909.01"

  test "Elixir and JSON inputs produce the same typed definition" do
    input = definition_input()

    assert {:ok, from_elixir} =
             CallDefinition.new(input, resource_id: "support", revision: 7)

    assert {:ok, from_json} =
             input
             |> JSON.encode!()
             |> CallDefinition.from_json(resource_id: "support", revision: 7)

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
      {Map.delete(definition_input(), :entry_caller), ["entry_caller"]},
      {%{definition_input() | entry_caller: 12}, ["entry_caller"]},
      {%{definition_input() | entry_caller: "missing"}, ["entry_caller"]},
      {%{definition_input() | entry_receiver: "caller"}, ["entry_receiver"]}
    ]

    for {input, path} <- cases do
      assert {:error,
              %Error{
                code: :invalid_call_definition,
                message: "The call definition is invalid.",
                details: %{"path" => ^path}
              }} = CallDefinition.new(input, resource_id: "support", revision: 7)
    end
  end

  test "rejects unsupported schema versions, fields, and participant options" do
    cases = [
      {%{definition_input() | schema_version: "20260906.02"}, ["schema_version"]},
      {Map.put(definition_input(), :provider_api_key, "do-not-echo-me"), ["provider_api_key"]},
      {Map.put(definition_input(), :media_policy, %{record_audio: false}), ["media_policy"]},
      {put_in(definition_input(), [:participants, "caller", :prompt], "wrong kind"),
       ["participants", "caller", "prompt"]},
      {put_in(definition_input(), [:participants, "caller", :connection, :service], "sip"),
       ["participants", "caller", "connection", "service"]},
      {put_in(
         definition_input(),
         [:participants, "reception", :tools, "get_current_time", :type],
         "mcp"
       ), ["participants", "reception", "tools", "get_current_time", "type"]},
      {put_in(
         definition_input(),
         [:participants, "reception", :tools],
         %{"transfer" => %{type: "host", tool: "get_current_time"}}
       ), ["participants", "reception", "tools", "transfer"]},
      {put_in(
         definition_input(),
         [:participants, "reception", :while_present],
         %{record_audio: false}
       ), ["participants", "reception", "while_present"]},
      {put_in(definition_input(), [:participants, "reception", :transfers], ["caller"]),
       ["participants", "reception", "transfers"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_definition, details: details}} =
               CallDefinition.new(input, resource_id: "support", revision: 7)

      assert details["path"] == path
      refute inspect(details) =~ "do-not-echo-me"
    end
  end

  test "invocation identity comes from trusted options and entry overrides are rejected" do
    input = %{
      call_definition: %{id: "support", revision: 7},
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
    assert invocation.definition_id == "support"
    assert invocation.definition_revision == 7
    assert invocation.transport == :web

    for forbidden <- [:tenant_id, :entry_caller, :entry_receiver] do
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

  test "compiles a pinned plan from closed capability and host-tool registries" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 7)

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: "call-one",
               room_id: "room-one"
             )

    registries = registries()

    assert {:ok, %ResolvedCallPlan{} = plan} =
             DefinitionCompiler.compile(definition, invocation, registries)

    assert plan.definition_id == "support"
    assert plan.definition_revision == 7
    assert plan.schema_version == @schema_version
    assert plan.tenant_id == "tenant-demo"
    assert plan.call_id == "call-one"
    assert plan.room_id == "room-one"
    assert plan.entry_caller == "caller"
    assert plan.entry_receiver == "reception"
    assert plan.tool_visibility == %ResolvedToolVisibility{default: :hidden, overrides: %{}}

    caller = plan.participants["caller"]
    receiver = plan.participants["reception"]

    assert caller.definition_key == "caller"
    assert receiver.definition_key == "reception"
    assert caller.participant_id != receiver.participant_id
    assert caller.activation_id == nil
    assert String.starts_with?(receiver.activation_id, "act_")

    assert %CapabilitySelection{
             kind: :speech_to_text,
             profile: "default-stt",
             provider: :test_stt,
             options: %{language: "en"}
           } = caller.capabilities.speech_to_text

    assert receiver.capabilities.speech_to_text == nil

    assert %CapabilitySelection{
             kind: :model_inference,
             profile: "careful-model",
             provider: :test_model,
             options: %{model: "careful"}
           } = receiver.capabilities.model_inference

    assert %ToolBinding{
             name: "get_current_time",
             action: CurrentTime,
             type: :host
           } = receiver.tools["get_current_time"]

    changed =
      put_in(registries, [:capability_profiles, "careful-model", :options, :model], "changed")

    assert get_in(changed, [:capability_profiles, "careful-model", :options, :model]) == "changed"
    assert receiver.capabilities.model_inference.options == %{model: "careful"}
  end

  test "validates and resolves participant-local tool visibility overrides" do
    reception = get_in(definition_input(), [:participants, "reception"])

    input =
      definition_input()
      |> Map.put(:tool_visibility, "full")
      |> Map.put(:tool_visibility_overrides, %{
        "reception" => %{"get_current_time" => "metadata"},
        "billing" => %{"get_current_time" => "hidden"}
      })
      |> put_in([:participants, "billing"], reception)

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 7)

    assert definition.tool_visibility == %ToolVisibility{
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

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())

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
      {Map.put(definition_input(), :tool_visibility, "verbose"), ["tool_visibility"]},
      {Map.put(definition_input(), :tool_visibility_overrides, []),
       ["tool_visibility_overrides"]},
      {Map.put(definition_input(), :tool_visibility_overrides, %{"missing" => %{}}),
       ["tool_visibility_overrides", "missing"]},
      {Map.put(definition_input(), :tool_visibility_overrides, %{"caller" => %{}}),
       ["tool_visibility_overrides", "caller"]},
      {Map.put(definition_input(), :tool_visibility_overrides, %{"reception" => []}),
       ["tool_visibility_overrides", "reception"]},
      {Map.put(definition_input(), :tool_visibility_overrides, %{
         "reception" => %{"missing" => "full"}
       }), ["tool_visibility_overrides", "reception", "missing"]},
      {Map.put(definition_input(), :tool_visibility_overrides, %{
         "reception" => %{"get_current_time" => "verbose"}
       }), ["tool_visibility_overrides", "reception", "get_current_time"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_definition, details: %{"path" => ^path}}} =
               CallDefinition.new(input, resource_id: "support", revision: 7)
    end
  end

  test "creates fresh runtime participant and activation identities for every call" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 7)

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

    assert {:ok, first} = DefinitionCompiler.compile(definition, first_invocation, registries())
    assert {:ok, second} = DefinitionCompiler.compile(definition, second_invocation, registries())

    refute first.call_id == second.call_id
    refute first.room_id == second.room_id

    refute first.participants["caller"].participant_id ==
             second.participants["caller"].participant_id

    refute first.participants["reception"].activation_id ==
             second.participants["reception"].activation_id
  end

  test "fails safely when a profile or tool is unavailable or aliases do not match" do
    cases = [
      {put_in(definition_input(), [:defaults, :capabilities, :speech_to_text], "missing"),
       registries(), ["defaults", "capabilities", "speech_to_text"]},
      {put_in(
         definition_input(),
         [:participants, "reception", :tools],
         %{"clock" => %{type: "host", tool: "get_current_time"}}
       ), registries(), ["participants", "reception", "tools", "clock"]},
      {definition_input(), put_in(registries(), [:host_tools], %{}),
       ["participants", "reception", "tools", "get_current_time"]}
    ]

    for {input, registry, path} <- cases do
      assert {:ok, definition} =
               CallDefinition.new(input, resource_id: "support", revision: 7)

      assert {:ok, invocation} =
               CallInvocation.new(invocation_input(),
                 tenant_id: "tenant-demo",
                 actor_id: "actor-demo"
               )

      assert {:error, %Error{code: :call_definition_resolution_failed, details: details}} =
               DefinitionCompiler.compile(definition, invocation, registry)

      assert details["path"] == path
    end
  end

  defp definition_input do
    %{
      schema_version: @schema_version,
      name: "Customer support",
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{
        capabilities: %{
          speech_to_text: "default-stt",
          model_inference: "default-model",
          text_to_speech: "default-voice"
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
          capabilities: %{model_inference: "careful-model"},
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
      call_definition: %{id: "support", revision: 7},
      initial_variables: %{},
      transport: %{type: "web"}
    }
  end

  defp registries do
    %{
      capability_profiles: %{
        "default-stt" => %{
          kind: :speech_to_text,
          provider: :test_stt,
          options: %{language: "en"}
        },
        "default-model" => %{
          kind: :model_inference,
          provider: :test_model,
          options: %{model: "default"}
        },
        "careful-model" => %{
          kind: :model_inference,
          provider: :test_model,
          options: %{model: "careful"}
        },
        "default-voice" => %{
          kind: :text_to_speech,
          provider: :test_tts,
          options: %{voice: "default"}
        }
      },
      host_tools: %{"get_current_time" => CurrentTime}
    }
  end
end
