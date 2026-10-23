defmodule Vxpipe.Calls.DemoSamplesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{DemoSamples, InstallationOperator}
  alias Vxpipe.Identity.Principal

  @tenant "DEMOabcdefgh1234"

  test "requires the actual browser actor and both grants before repository access" do
    options = [demo_tenant_repository: {MissingRepository, nil}]

    for actor <- [
          nil,
          InstallationOperator.authority(),
          principal([]),
          principal(["tenants.write"]),
          principal(["call_specs.write"])
        ] do
      assert {:error, :forbidden} = DemoSamples.install(actor, @tenant, options)
    end

    actor = %{principal(["tenants.write", "call_specs.write"]) | assigned_tenants: %{}}
    assert {:error, :forbidden} = DemoSamples.install(actor, @tenant, options)
  end

  test "rejects an invalid tenant locator before repository access" do
    actor = principal(["tenants.write", "call_specs.write"])
    assert {:error, :invalid_tenant_key} = DemoSamples.install(actor, "", [])
  end

  test "ships three parseable, versioned sample call specs" do
    entries = DemoSamples.catalog("google")

    assert Enum.map(entries, & &1.id) == [
             "sample-voice-conversation",
             "sample-agent-handoff",
             "sample-human-handoff"
           ]

    for entry <- entries do
      assert entry.version == 1

      assert {:ok, call_spec} =
               Vxpipe.CallEngine.CallSpec.new(entry.source, resource_id: entry.id, revision: 1)

      assert call_spec.default_capabilities.model_inference.provider == "google"
      assert call_spec.default_capabilities.text_to_speech.model == "flux"
      assert call_spec.default_capabilities.text_to_speech.options == %{"voice" => "haley"}
    end

    assert Enum.all?(DemoSamples.catalog("zenmux"), fn entry ->
             {:ok, call_spec} =
               Vxpipe.CallEngine.CallSpec.new(entry.source, resource_id: entry.id, revision: 1)

             call_spec.default_capabilities.model_inference.provider == "zenmux"
           end)
  end

  defp principal(grants) do
    %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(grants),
      assigned_tenants: %{@tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }
  end
end
