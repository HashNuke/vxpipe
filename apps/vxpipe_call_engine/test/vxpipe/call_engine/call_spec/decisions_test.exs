defmodule Vxpipe.CallEngine.CallSpec.DecisionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.CallEngine.CallSpec.CapabilityRequirements
  alias Vxpipe.CallEngine.CallSpecCompiler
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ModelCatalog
  alias Vxpipe.CallEngine.Tool.CurrentTime

  @new_schema "20261128.01"
  @old_schema "20261125.01"

  test "parses call-wide decisions on the new schema and pins it in the compiled plan" do
    assert {:ok, call_spec} =
             CallSpec.new(decisions_input(), resource_id: "support", revision: 3)

    assert call_spec.schema_version == @new_schema
    assert call_spec.default_capabilities.decisions.provider == "openai"
    assert call_spec.default_capabilities.decisions.model == "gpt-6-luna"
    assert call_spec.default_capabilities.decisions.kind == :decisions

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    assert plan.schema_version == @new_schema
    assert plan.decisions.provider == "openai"
    assert plan.decisions.model == "gpt-6-luna"
    assert plan.decisions == call_spec.default_capabilities.decisions
  end

  test "absent decisions compiles to nil when no guardrails are enabled" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 3)

    assert is_nil(call_spec.default_capabilities.decisions)

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    assert is_nil(plan.decisions)
  end

  test "rejects decisions on previously supported schema versions" do
    input =
      call_spec_input()
      |> Map.put(:schema_version, @old_schema)
      |> put_in([:defaults, :capabilities, :decisions], %{
        provider: "openai",
        model: "gpt-6-luna"
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["defaults", "capabilities", "decisions"]
  end

  test "rejects per-participant decisions setting" do
    input =
      put_in(decisions_input(), [:participants, "reception", :capabilities, :decisions], %{
        provider: "openai",
        model: "gpt-6-luna"
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == [
             "participants",
             "reception",
             "capabilities",
             "decisions"
           ]
  end

  test "rejects enabled guardrails lacking a valid decisions selection" do
    input =
      put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
        before_turn: [
          %{
            id: "private_request",
            question: "Is this about their account?",
            required_answer: "yes"
          }
        ]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["defaults", "capabilities", "decisions"]
  end

  test "rejects before_turn guardrails on speech-to-speech agents" do
    input =
      decisions_input()
      |> put_in([:participants, "reception", :capabilities], %{
        speech_to_speech: %{provider: "morse", model: "morse-duplex"}
      })
      |> put_in([:participants, "reception", :guardrails], %{
        before_turn: [%{id: "q_one", question: "Is this private?", required_answer: "yes"}]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["participants", "reception", "guardrails", "before_turn"]
  end

  test "rejects after_turn guardrails without effective LLM and TTS" do
    input =
      decisions_input()
      |> put_in([:defaults, :capabilities], %{
        speech_to_text: %{provider: "morse", model: "morse"},
        text_to_speech: %{provider: "morse", model: "morse"},
        decisions: %{
          provider: "openai",
          model: "gpt-6-luna",
          credential_name: "guardrails-primary"
        }
      })
      |> put_in([:participants, "reception", :capabilities], %{})
      |> put_in([:participants, "reception", :guardrails], %{
        after_turn: [
          %{id: "q_two", question: "Does this disclose details?", required_answer: "no"}
        ]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["participants", "reception", "guardrails", "after_turn"]
  end

  test "credential requirements include decisions only when guardrails are enabled" do
    assert {:ok, guarded} =
             CallSpec.new(guarded_decisions_input(), resource_id: "support", revision: 3)

    required = CapabilityRequirements.credentials(guarded)

    assert Enum.any?(required, fn {selection, path} ->
             selection.kind == :decisions and path == ["defaults", "capabilities", "decisions"]
           end)

    assert {:ok, unguarded} =
             CallSpec.new(decisions_input(), resource_id: "support", revision: 3)

    unguarded_required = CapabilityRequirements.credentials(unguarded)

    refute Enum.any?(unguarded_required, fn {selection, _path} ->
             selection.kind == :decisions
           end)
  end

  test "decisions selection validates through the capability catalog" do
    assert {:ok, spec} =
             CallSpec.new(decisions_input(), resource_id: "support", revision: 3)

    assert :ok = CapabilityCatalog.validate(spec.default_capabilities.decisions)
    assert {:ok, _adapter} = CapabilityCatalog.adapter(spec.default_capabilities.decisions)
    assert CapabilityCatalog.credential_required?(spec.default_capabilities.decisions)
  end

  test "fixture selections cannot resolve a hosted adapter and unknown providers return a field error" do
    {:ok, spec} = CallSpec.new(decisions_input(), resource_id: "support", revision: 3)
    selection = spec.default_capabilities.decisions
    local = %{selection | provider: "fixture", model: "fixture", credential_name: nil}

    assert :ok = CapabilityCatalog.validate(local)
    assert {:error, :unsupported_capability} = CapabilityCatalog.adapter(local)

    assert {:error, :unsupported_capability} =
             CapabilityCatalog.validate(%{selection | provider: "unknown"})

    assert {:error, :unsupported_capability} =
             CapabilityCatalog.adapter(%{selection | model: "unknown"})
  end

  test "eligible decisions models are listed for authoring" do
    assert {:ok, providers} = ModelCatalog.providers("decisions")
    assert Enum.map(providers, & &1.id) == ["google", "jev", "openai"]

    for provider <- providers do
      assert {:ok, models} = ModelCatalog.models(provider.id, "decisions")
      assert models != []
      assert Enum.count(models, & &1.default) == 1
    end
  end

  defp decisions_input do
    call_spec_input()
    |> put_in([:defaults, :capabilities, :decisions], %{
      provider: "openai",
      model: "gpt-6-luna",
      credential_name: "guardrails-primary"
    })
  end

  defp guarded_decisions_input do
    decisions_input()
    |> put_in([:participants, "reception", :guardrails], %{
      before_turn: [
        %{id: "private_request", question: "Is this about their account?", required_answer: "yes"}
      ]
    })
  end

  defp call_spec_input do
    %{
      schema_version: @new_schema,
      name: "Customer support",
      incoming_call: %{caller: "caller", handled_by: "reception"},
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
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          description: "The receiving agent",
          prompt: "Answer clearly.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "careful"}},
          tools: %{"get_current_time" => %{type: "host", tool: "get_current_time"}},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 1_800_000}
    }
  end

  defp invocation_input do
    %{call_spec: %{id: "support", revision: 3}, initial_variables: %{}, transport: %{type: "web"}}
  end

  defp registries do
    %{host_tools: %{"get_current_time" => CurrentTime}}
  end
end
