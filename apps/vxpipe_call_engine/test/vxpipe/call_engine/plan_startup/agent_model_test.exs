defmodule Vxpipe.CallEngine.PlanStartup.AgentModelTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.PlanStartup.AgentModel
  alias Vxpipe.CallEngine.TestTenantCredentialSource

  test "constructs the existing Zenmux adapter from only the selected tenant binding" do
    routing = %{"fallback" => "anthropic", "routing" => %{"providers" => ["openai", "anthropic"]}}

    selection = %{
      selection()
      | provider: "zenmux",
        model: "openai/gpt-5",
        credential_name: "router",
        provider_options: %{"provider" => routing}
    }

    bindings = %{{"tenant-model", "zenmux", "router"} => %{"api_key" => "zenmux-tenant-marker"}}

    options =
      Keyword.put(options(), :credential_source, {TestTenantCredentialSource, {self(), bindings}})

    assert {:ok, model} = AgentModel.resolve(selection, "tenant-model", options)
    assert_receive {:tenant_credential_resolved, "tenant-model", "zenmux", "router"}
    assert model.configuration.api_key == "zenmux-tenant-marker"
    assert model.configuration.model.provider == :zenmux
    assert model.configuration.model.id == "openai/gpt-5"
    assert model.configuration.generation_options[:temperature] == 0.2

    assert model.configuration.generation_options[:provider_options] == [
             provider: %{fallback: "anthropic", routing: %{providers: ["openai", "anthropic"]}}
           ]

    refute inspect(model) =~ "tenant-marker"

    for {tenant, input} <- [
          {"other-tenant", selection},
          {"tenant-model", %{selection | credential_name: "default"}}
        ] do
      assert {:error, :unsupported_provider_options} = AgentModel.resolve(input, tenant, options)
    end
  end

  test "translates the inline selection without merging application authentication or options" do
    assert {:ok, model} = AgentModel.resolve(selection(), "tenant-model", options())
    assert model.configuration.api_key == "tenant-synthetic-key"
    assert model.configuration.model.provider == :google
    assert model.configuration.model.id == "gemini-2.5-flash"
    assert model.configuration.generation_options[:temperature] == 0.2
    refute inspect(model) =~ "synthetic-key"
  end

  test "resolves an OpenAI model with the tenant's saved API key" do
    input = %{selection() | provider: "openai", model: "gpt-5", options: %{}}
    bindings = %{{"tenant-model", "openai", "default"} => %{"api_key" => "openai-tenant-marker"}}

    options =
      Keyword.put(options(), :credential_source, {TestTenantCredentialSource, {self(), bindings}})

    assert {:ok, model} = AgentModel.resolve(input, "tenant-model", options)
    assert model.configuration.api_key == "openai-tenant-marker"
    assert model.configuration.model.provider == :openai
    assert model.configuration.model.id == "gpt-5"
    refute inspect(model) =~ "tenant-marker"
  end

  test "new LLM services validate and resolve only the selected scoped credential" do
    for {provider, model_id, native} <- [
          {"deepseek", "deepseek-flash", :deepseek},
          {"openrouter", "google/gemini-3.5-flash-lite", :openrouter},
          {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b", :fireworks_ai}
        ] do
      input = %{
        selection()
        | provider: provider,
          model: model_id,
          options: %{"max_tokens" => 256}
      }

      bindings = %{
        {"tenant-model", provider, "default"} => %{"api_key" => "scoped-provider-marker"}
      }

      settings =
        Keyword.put(
          options(),
          :credential_source,
          {TestTenantCredentialSource, {self(), bindings}}
        )

      assert :ok = Vxpipe.CallEngine.CapabilityCatalog.validate(input)

      assert {:ok, Vxpipe.AgentRuntime.Provider.ReqLLM} =
               Vxpipe.CallEngine.CapabilityCatalog.adapter(input)

      assert {:ok, model} = AgentModel.resolve(input, "tenant-model", settings)
      assert_receive {:tenant_credential_resolved, "tenant-model", ^provider, "default"}
      assert model.configuration.api_key == "scoped-provider-marker"
      assert model.configuration.model.provider == native
      assert model.configuration.model.id == model_id
      assert model.model == provider <> ":" <> model_id
      refute inspect(model) =~ "scoped-provider-marker"

      assert {:error, :unsupported_provider_options} =
               AgentModel.resolve(input, "other-tenant", settings)
    end
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
