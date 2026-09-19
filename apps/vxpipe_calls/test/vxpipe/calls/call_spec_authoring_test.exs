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
end
