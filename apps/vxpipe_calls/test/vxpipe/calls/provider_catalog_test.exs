defmodule Vxpipe.Calls.ProviderCatalogTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{InstallationOperator, Principal, TestOperatorCredentialRepository}

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "lists usable tenant and inherited bindings without returning credential metadata" do
    bindings = [
      binding("google", :platform, :connected),
      binding("deepgram", :tenant, :invalid),
      binding("cartesia", :tenant, :connected)
    ]

    for authority <- [InstallationOperator.authority(), principal(@tenant, [:admin])] do
      assert {:ok, %{providers: providers}} =
               Vxpipe.Calls.list_providers(
                 authority,
                 @tenant,
                 "speech_to_text",
                 options(bindings)
               )

      assert Enum.find(providers, &(&1.id == "google")).credential_available
      assert Enum.find(providers, &(&1.id == "cartesia")).credential_available
      refute Enum.find(providers, &(&1.id == "deepgram")).credential_available
      refute Enum.find(providers, &(&1.id == "elevenlabs")).credential_available

      assert %{credential_required: false, credential_available: true} =
               Enum.find(providers, &(&1.id == "morse"))

      assert_received {:operator_bindings_requested, @tenant}
      encoded = JSON.encode!(providers)
      refute encoded =~ "private-sentinel"
      refute encoded =~ "credential_id"
      refute encoded =~ "saved_fields"
    end
  end

  test "requires an operator or the same tenant's admin before reading bindings" do
    for {authority, reason} <- [
          {principal(@other, [:admin]), :tenant_access_forbidden},
          {principal(@tenant, [:call]), :insufficient_scope},
          {nil, :authoring_authority_required}
        ] do
      assert {:error, ^reason} =
               Vxpipe.Calls.list_providers(authority, @tenant, "text_to_speech", options([]))

      assert {:error, ^reason} =
               Vxpipe.Calls.list_provider_models(
                 authority,
                 @tenant,
                 "deepgram",
                 "text_to_speech",
                 options([])
               )

      refute_received {:operator_bindings_requested, _}
    end
  end

  test "a repository directory from another tenant is rejected" do
    assert {:error, :service_directory_unavailable} =
             Vxpipe.Calls.list_providers(
               InstallationOperator.authority(),
               @tenant,
               "speech_to_text",
               options([], @other)
             )
  end

  test "models retain separate public model and voice and do not require a credential" do
    assert {:ok, %{models: [%{id: "flux", voices: %{default: "hannah"}}]}} =
             Vxpipe.Calls.list_provider_models(
               principal(@tenant, [:admin]),
               @tenant,
               "deepgram",
               "text_to_speech",
               options([])
             )

    assert {:error, :unsupported_provider} =
             Vxpipe.Calls.list_provider_models(
               principal(@tenant, [:admin]),
               @tenant,
               "unknown",
               "text_to_speech",
               options([])
             )

    assert {:error, :invalid_capability} =
             Vxpipe.Calls.list_providers(
               principal(@tenant, [:admin]),
               @tenant,
               "unknown",
               options([])
             )
  end

  defp principal(tenant, scopes),
    do: %Principal{tenant_key: tenant, api_key_id: "key", scopes: MapSet.new(scopes)}

  defp options(bindings, tenant \\ @tenant) do
    directory = %{tenant: %{key: tenant, name: "Example"}, bindings: bindings}

    [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, directory})
    ]
  end

  defp binding(provider, source, status) do
    %{
      provider: provider,
      name: "default",
      source: source,
      status: status,
      credential_id: "private-sentinel",
      platform_available: true,
      saved_fields: ["api_key"],
      last_validated_at: nil,
      payload: %{api_key: "private-sentinel"}
    }
  end
end
