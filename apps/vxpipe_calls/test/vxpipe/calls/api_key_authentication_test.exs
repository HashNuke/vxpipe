defmodule Vxpipe.Calls.ApiKeyAuthenticationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Principal, TestMemoryRepository}

  setup do
    repository = start_supervised!(TestMemoryRepository)
    [options: [credential_repository: TestMemoryRepository.credential_repository(repository)]]
  end

  test "discovers the tenant and preserves exactly the stored scopes", %{options: options} do
    for scopes <- [[:admin], [:calls], [:admin, :calls]] do
      assert {:ok, tenant, issued} = Calls.bootstrap_tenant("Tenant", scopes, options)

      assert {:ok, principal} = Calls.authenticate_api_key(issued.secret, options)

      assert principal == %Principal{
               tenant_key: tenant.key,
               api_key_id: issued.id,
               scopes: MapSet.new(scopes)
             }
    end
  end

  test "reauthentication rejects revoked keys without invalidating another key", %{
    options: options
  } do
    {:ok, tenant, first} = Calls.bootstrap_tenant("Tenant", [:calls], options)
    {:ok, second} = Calls.issue_api_key(tenant.key, "Second", [:calls], options)
    assert {:ok, _} = Calls.authenticate_api_key(first.secret, options)
    assert {:ok, _} = Calls.revoke_api_key(tenant.key, first.id, options)
    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(first.secret, options)
    assert {:ok, %Principal{api_key_id: id}} = Calls.authenticate_api_key(second.secret, options)
    assert id == second.id
  end

  test "ambiguous tenant digests fail closed while existing tenant authentication works", %{
    options: options
  } do
    options = Keyword.put(options, :api_key_generator, fn -> "vxp_shared-synthetic-secret" end)
    {:ok, first, issued} = Calls.bootstrap_tenant("One", [:calls], options)
    {:ok, second, _} = Calls.bootstrap_tenant("Two", [:admin], options)

    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(issued.secret, options)
    assert {:ok, _} = Calls.authenticate(first.key, issued.secret, :calls, options)
    assert {:ok, _} = Calls.authenticate(second.key, issued.secret, :admin, options)

    assert {:ok, _} = Calls.revoke_api_key(first.key, issued.id, options)
    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(issued.secret, options)
  end

  test "rejects unknown, malformed and legacy operator secrets", %{options: options} do
    for secret <- [nil, %{}, "", String.duplicate("a", 257), "vxop_" <> String.duplicate("a", 43)] do
      assert {:error, :invalid_api_key} = Calls.authenticate_api_key(secret, options)
    end

    assert {:error, :invalid_api_key} = Calls.authenticate_api_key("unknown", options)
  end

  test "does not disguise unavailable authentication storage as an invalid key" do
    assert {:error, :repository_unavailable} =
             Calls.authenticate_api_key("vxp_synthetic-secret",
               credential_repository: {__MODULE__, :unavailable}
             )
  end

  def fetch_api_key_by_digest(:unavailable, _digest), do: {:error, :repository_unavailable}
end
