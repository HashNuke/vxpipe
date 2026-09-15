defmodule Vxpipe.CallEngine.PlanStartup.AgentModelTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.PlanStartup.AgentModel
  alias Vxpipe.CallEngine.TestTenantCredentialSource

  test "translates the inline selection without merging application authentication or options" do
    assert {:ok, model} = AgentModel.resolve(selection(), "tenant-model", options())
    assert model.configuration.api_key == "tenant-synthetic-key"
    assert model.configuration.model.provider == :google
    assert model.configuration.model.id == "gemini-2.5-flash"
    assert model.configuration.generation_options[:temperature] == 0.2
    refute inspect(model) =~ "synthetic-key"
  end

  test "does not use application credentials for another tenant" do
    assert {:error, :unsupported_provider_options} =
             AgentModel.resolve(selection(), "other-tenant", options())
  end

  test "rejects executable generation hooks and unsupported provider routing" do
    for injected <- [
          %{selection() | options: %{"output_repair" => fn _ -> :ok end}},
          %{selection() | provider_options: %{"provider" => %{"fallback" => "anthropic"}}}
        ] do
      assert {:error, :unsupported_provider_options} =
               AgentModel.resolve(injected, "tenant-model", options())
    end
  end

  test "the credential-free fixture selection cannot activate the hosted ReqLLM adapter" do
    fixture = %{
      selection()
      | provider: "fixture",
        model: "google:gemini-2.5-flash",
        credential_name: nil,
        options: %{}
    }

    for provider_options <- [[api_key: "fixture-private-marker"], []] do
      runtime = [fixture: {Vxpipe.AgentRuntime.Provider.ReqLLM, provider_options}]

      assert {:error, :unsupported_provider_options} =
               AgentModel.resolve(fixture, "tenant-model", agent_runtime: runtime)
    end
  end

  defp selection do
    %CapabilitySelection{
      kind: :model_inference,
      provider: "google",
      model: "gemini-2.5-flash",
      credential_name: "default",
      options: %{"temperature" => 0.2},
      provider_options: %{}
    }
  end

  defp options do
    bindings = %{{"tenant-model", "google", "default"} => %{"api_key" => "tenant-synthetic-key"}}

    [
      credential_source: {TestTenantCredentialSource, {self(), bindings}},
      agent_runtime: [
        model_provider_options: [
          api_key: "application-synthetic-key",
          generation_options: [temperature: 0.7]
        ]
      ]
    ]
  end
end
