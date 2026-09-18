defmodule Vxpipe.Gateway.TrustedCallTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.TrustedCall

  test "trusted input uses inline selections with only the host-tool registry" do
    assert {:ok, trusted} = TrustedCall.new(options())
    assert trusted.registries == %{host_tools: %{}}
    assert trusted.call_spec.default_capabilities.model_inference.provider == "fixture"
  end

  test "the retired capability-profile configuration is rejected" do
    assert {:error, :invalid_config} =
             TrustedCall.new(Keyword.put(options(), :capability_profiles, %{}))
  end

  defp options do
    [
      resource_id: "trusted-inline",
      revision: 1,
      host_tools: %{},
      call_spec: %{
        schema_version: "20260915.01",
        entry_caller: "caller",
        entry_receiver: "assistant",
        wait_sounds: nil,
        defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
        participants: %{
          "caller" => %{
            type: "human",
            connection: %{service: "web", mode: "receive", admission: "start_call"}
          },
          "assistant" => %{
            type: "agent",
            prompt: "Answer briefly.",
            first_message: %{mode: "wait_for_input"},
            tools: %{},
            transfers: []
          }
        }
      }
    ]
  end
end
