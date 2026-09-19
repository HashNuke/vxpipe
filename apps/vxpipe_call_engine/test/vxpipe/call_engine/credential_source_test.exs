defmodule Vxpipe.CallEngine.CredentialSourceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CredentialSource, ProviderCredential, TestTenantCredentialSource}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  test "fresh resolution rejects a foreign or malformed owner even when the consumer matches" do
    tenant = "tenant-one"

    selection = %CapabilitySelection{
      kind: :model_inference,
      provider: "google",
      model: "gemini-2.5-flash",
      credential_name: "shared",
      options: %{},
      provider_options: %{}
    }

    for owner <- [{:tenant, "tenant-two"}, :invalid] do
      credential = %ProviderCredential{
        id: "credential",
        tenant_id: tenant,
        owner: owner,
        provider: "google",
        name: "shared",
        version: 1,
        auth_kind: "api_key",
        payload: %{"api_key" => "synthetic-example"}
      }

      options = [
        credential_source:
          {TestTenantCredentialSource, {self(), %{{tenant, "google", "shared"} => credential}}}
      ]

      assert {:error, :provider_credential_unavailable} =
               CredentialSource.resolve(tenant, selection, options)
    end
  end
end
