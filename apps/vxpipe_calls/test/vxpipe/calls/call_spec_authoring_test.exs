defmodule Vxpipe.Calls.CallSpecAuthoringTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{CallSpecAuthoring, InstallationOperator, Principal}

  test "rejects missing authority, tenant substitution and calls-only keys before spec processing" do
    author = %Principal{
      tenant_key: "AAAAAAAAAAAAAAAA",
      api_key_id: "key",
      scopes: MapSet.new([:admin])
    }

    calls = %{author | scopes: MapSet.new([:calls])}

    for {principal, tenant, reason} <- [
          {nil, author.tenant_key, :authoring_authority_required},
          {%InstallationOperator{grant: :invalid}, author.tenant_key,
           :authoring_authority_required},
          {author, "BBBBBBBBBBBBBBBB", :tenant_access_forbidden},
          {calls, author.tenant_key, :insufficient_scope}
        ] do
      assert {:error, ^reason} = CallSpecAuthoring.save(principal, tenant, %{}, [])
      assert {:error, ^reason} = CallSpecAuthoring.publish(principal, tenant, "spec", 1, [])
    end
  end

  test "authors may append to existing IDs but cannot allocate a chosen ID" do
    alias Vxpipe.Calls.{Administration, CallSpecs, TestMemoryRepository}
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("Authoring IDs", [:admin], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other tenant", [:admin], options)

    source = %{
      "schema_version" => "20261004.01",
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }

    principal = %Principal{
      tenant_key: tenant.key,
      api_key_id: "key",
      scopes: MapSet.new([:admin])
    }

    {:ok, foreign} = CallSpecs.save(other.key, source, options)

    for authority <- [principal, InstallationOperator.authority()] do
      for id <- ["new", "11111111-1111-4111-8111-111111111111", foreign.call_spec_id] do
        assert {:error, :not_found} =
                 CallSpecAuthoring.save(
                   authority,
                   tenant.key,
                   source,
                   Keyword.put(options, :call_spec_id, id)
                 )

        assert {:error, :not_found} = CallSpecs.fetch(tenant.key, id, 1, options)
      end

      assert {:ok, first} = CallSpecAuthoring.save(authority, tenant.key, source, options)

      assert first.call_spec_id =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      assert {:ok, second} =
               CallSpecAuthoring.save(
                 authority,
                 tenant.key,
                 Map.put(source, "name", "Changed"),
                 Keyword.put(options, :call_spec_id, first.call_spec_id)
               )

      assert second.call_spec_id == first.call_spec_id
      assert second.revision == 2
      assert {:ok, original} = CallSpecs.fetch(tenant.key, first.call_spec_id, 1, options)
      assert original.source == source
    end
  end
end
