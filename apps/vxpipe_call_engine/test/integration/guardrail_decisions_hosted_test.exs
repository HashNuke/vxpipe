defmodule Vxpipe.CallEngine.Integration.GuardrailDecisionsHostedTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{TestGuardrailDecisionsScenario, TestTenantCredentialSource}

  @moduletag :capture_log
  @moduletag timeout: 90_000

  for {provider, model, usage} <- [
        {"openai", "gpt-6-luna",
         %{"input_tokens" => 17, "output_tokens" => 2, "total_tokens" => 19}},
        {"google", "gemini-decision-1", "unknown"},
        {"jev", "jev-1.14.0", %{"input_tokens" => 17, "output_tokens" => 2}}
      ] do
    test "#{provider} runs the hosted room scenarios against its local HTTP fixture" do
      tenant = "GuardrailsQA0001"
      provider = unquote(provider)
      connection = "policy"
      selection = %{provider: provider, model: unquote(model), credential_name: connection}
      bindings = %{{tenant, provider, connection} => %{"api_key" => "synthetic"}}

      samples =
        TestGuardrailDecisionsScenario.run(tenant, selection,
          credential_source: {TestTenantCredentialSource, {self(), bindings}},
          plug: &TestGuardrailDecisionsScenario.fixture/1
        )

      assert Enum.all?(samples, &(&1["attempt_usage"] == [unquote(Macro.escape(usage))]))
    end
  end
end
