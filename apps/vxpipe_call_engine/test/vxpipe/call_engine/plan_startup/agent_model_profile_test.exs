defmodule Vxpipe.CallEngine.PlanStartup.AgentModelProfileTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: ReqLLMProvider
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.Config, as: ReqLLMConfig

  alias Vxpipe.CallEngine.CallDefinition.{
    CapabilitySelection,
    TransferPolicy,
    VariablePermissions
  }

  alias Vxpipe.CallEngine.PlanStartup.AgentActivation
  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    Capabilities,
    MediaPolicy,
    Participant,
    ToolVisibility
  }

  @routing %{
    fallback: "anthropic",
    routing: %{type: "priority", providers: ["openai", "anthropic"]}
  }

  test "merges validated generation options from the pinned model profile" do
    receiver =
      participant(%{
        model: "zenmux:openai/gpt-5",
        generation_options: [
          provider_options: [provider: @routing],
          temperature: 0.0
        ]
      })

    assert {:ok, activation} =
             AgentActivation.new(plan(receiver), receiver,
               owner: self(),
               validation_only: true,
               agent_runtime: runtime_settings()
             )

    assert %ReqLLMConfig{generation_options: options} = Keyword.fetch!(activation, :model)
    assert Keyword.fetch!(options, :provider_options) == [provider: @routing]
    assert Keyword.fetch!(options, :temperature) == 0.0
    assert Keyword.fetch!(options, :total_timeout) == 30_000
    refute inspect(activation) =~ "application-secret"
  end

  test "rejects profile generation options unsupported by the selected model provider" do
    receiver =
      participant(%{
        model: "google:gemini-3.5-flash-lite",
        generation_options: [provider_options: [provider: @routing]]
      })

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{
                "path" => ["participants", "receiver", "capabilities", "model_inference"]
              }
            }} =
             AgentActivation.new(plan(receiver), receiver,
               owner: self(),
               validation_only: true,
               agent_runtime: runtime_settings()
             )
  end

  test "rejects executable generation hooks from a model profile" do
    receiver =
      participant(%{
        model: "zenmux:openai/gpt-5",
        generation_options: [output_repair: fn _invalid -> {:ok, "repaired"} end]
      })

    assert {:error, %Error{code: :unsupported_call_plan}} =
             AgentActivation.new(plan(receiver), receiver,
               owner: self(),
               validation_only: true,
               agent_runtime: runtime_settings()
             )
  end

  defp runtime_settings do
    :vxpipe_call_engine
    |> Application.fetch_env!(Vxpipe.CallEngine.Application)
    |> Keyword.fetch!(:agent_runtime)
    |> Keyword.put(:model_provider, ReqLLMProvider)
    |> Keyword.put(
      :model_provider_options,
      api_key: "application-secret",
      generation_options: [temperature: 0.7, total_timeout: 30_000],
      streaming: false
    )
  end

  defp participant(profile_options) do
    %Participant{
      definition_key: "receiver",
      participant_id: "participant-receiver",
      activation_id: "activation-receiver",
      kind: :agent,
      description: nil,
      connection: nil,
      transfer_notice: nil,
      prompt: "Answer concisely.",
      first_message: :wait_for_input,
      first_message_text: nil,
      capabilities: %Capabilities{
        model_inference: %CapabilitySelection{
          kind: :model_inference,
          profile: "routed-model",
          provider: :req_llm,
          options: profile_options
        }
      },
      while_present: MediaPolicy.inherit(),
      tools: %{},
      transfers: [],
      transfer_history: nil,
      variable_permissions: %VariablePermissions{}
    }
  end

  defp plan(receiver) do
    %ResolvedCallPlan{
      definition_id: "definition-1",
      definition_revision: 1,
      schema_version: "20260910.02",
      tenant_id: "tenant-1",
      actor_id: "actor-1",
      call_id: "call-1",
      room_id: "room-1",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio: nil,
      media_policy: MediaPolicy.inherit(),
      participants: %{"receiver" => receiver},
      transfer_policy: %TransferPolicy{attempt_timeout_ms: 30_000},
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 1_800_000
    }
  end
end
