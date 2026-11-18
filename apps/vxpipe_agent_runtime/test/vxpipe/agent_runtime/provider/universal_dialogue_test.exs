defmodule Vxpipe.AgentRuntime.Provider.UniversalDialogueTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    Message,
    ModelCatalog,
    ModelRequest,
    ModelTool,
    ProviderSelection,
    SessionConfiguration
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  test "every installed LLM accepts modern sessions including unfamiliar resolved model IDs" do
    providers =
      for {provider, capabilities} <- Vxpipe.Providers.Registry.catalog(),
          :llm in capabilities,
          do: provider

    assert length(providers) >= 6

    for provider <- providers do
      assert {:ok, [model | _]} = ModelCatalog.models(provider)
      assert {:ok, options} = ProviderSelection.translate(provider, model.id, %{}, %{})
      assert {:ok, config} = Provider.new(Keyword.put(options, :api_key, "test-only"))

      for model <- [
            config.model,
            %{config.model | id: "future-model", provider_model_id: "future-model"}
          ] do
        selected = %{config | model: model}

        assert {:ok, _session} =
                 SessionConfiguration.new(
                   instructions: "Be concise",
                   history_mode: :host_settled,
                   reply_protocol: :mode_message_v1,
                   model_provider: Provider,
                   model: selected,
                   pending_context_source:
                     {Vxpipe.AgentRuntime.TestPendingContextSource,
                      %{owner: self(), result: {:ok, []}}},
                   event_destination: self()
                 ),
               provider
      end
    end
  end

  test "portable requests instruct strict JSON and retain native tools and provider options" do
    {:ok, options} = ProviderSelection.translate("google", "gemini-3.5-flash-lite", %{}, %{})
    {:ok, config} = Provider.new(Keyword.put(options, :api_key, "test-only"))

    tool = %ModelTool{
      name: "structured_output",
      description: "An ordinary authorized tool",
      input_schema: %{"type" => "object"}
    }

    request = %{
      ModelRequest.new([Message.user("Hello")], [tool], [], %{})
      | reply_protocol: :mode_message_v1
    }

    {_model, context, options} = Provider.prepare_request(config, request)
    assert [%{name: "structured_output"}] = options[:tools]
    assert options[:provider_options][:google_auth_header]
    refute Keyword.has_key?(options[:provider_options], :response_format)
    [system | _] = Elixir.ReqLLM.Context.to_list(context)
    assert system.role == :system
    assert Enum.map_join(system.content, & &1.text) =~ "agent_mode"
    assert Enum.map_join(system.content, & &1.text) =~ "JSON"
    refute Provider.supports_protocol?(config, :unknown_protocol, [])
  end
end
