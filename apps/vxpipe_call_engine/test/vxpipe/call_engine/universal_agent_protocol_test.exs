defmodule Vxpipe.CallEngine.UniversalAgentProtocolTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ModelCatalog

  alias Vxpipe.CallEngine.{
    AgentProtocol,
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    TestTurnCall
  }

  test "all installed LLM selections compile and pin the shared modern protocol" do
    {:ok, protocol} = AgentProtocol.capture()

    providers =
      for {provider, capabilities} <- Vxpipe.Providers.Registry.catalog(),
          :llm in capabilities,
          do: provider

    assert length(providers) >= 6

    for provider <- providers do
      {:ok, [model | _]} = ModelCatalog.models(provider)

      source =
        put_in(
          TestTurnCall.call_spec(),
          [:participants, "receiver", :capabilities, :model_inference],
          %{provider: provider, model: model.id}
        )

      assert {:ok, spec} = CallSpec.new(source, resource_id: "universal", revision: 1)

      assert {:ok, invocation} =
               CallInvocation.new(
                 %{
                   call_spec: %{id: "universal", revision: 1},
                   initial_variables: %{},
                   transport: %{type: "web"}
                 },
                 tenant_id: "tenant",
                 actor_id: "actor"
               )

      assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
      assert {:ok, modern} = AgentProtocol.pin(plan, protocol)
      assert modern.agent_protocol == protocol
      assert {:ok, _legacy} = AgentProtocol.pin(plan, nil)
      assert {:error, :invalid_protocol} = AgentProtocol.pin(plan, %{"version" => "unknown"})
    end
  end
end
