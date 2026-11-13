defmodule Vxpipe.Calls.VoiceCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    InstallationOperator,
    Principal,
    ProviderCredential,
    ResolvedProviderCredential,
    VoiceCatalog
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"
  @scope %{
    provider: "morse_code_api",
    model: "morse_v1",
    capability: "text_to_speech",
    credential_name: "speech"
  }

  test "authorizes tenant readers without granting credential management and preserves the selected binding" do
    assert {:ok, %{voices: [%{id: "morse"}]}} = request(actor(), @tenant, credential(@tenant))
    assert_received {:resolved, @tenant, "morse_code_api", "speech"}

    assert {:ok, %{providerName: "MorseCode API"}} =
             VoiceCatalog.request(
               actor(),
               @tenant,
               @scope,
               :describe,
               %{},
               options(credential(@tenant))
             )
  end

  test "denies other tenants, missing grants and narrowed delegation before credential lookup" do
    delegated = %{
      actor()
      | delegation: %{assigned_tenants: %{}, all_tenant_actions: MapSet.new()}
    }

    for {actor, tenant} <- [
          {actor(), @other},
          {%{actor() | grants: MapSet.new()}, @tenant},
          {delegated, @tenant}
        ] do
      assert {:error, :forbidden} = request(actor, tenant, credential(tenant))
      refute_received {:resolved, _, _, _}
    end
  end

  test "platform credentials require platform authoring permission; tenant API keys cannot inherit" do
    assert {:error, :provider_service_forbidden} =
             request(actor(), @tenant, credential(:platform))

    assert {:ok, _} = request(actor(["platform_services.read"]), @tenant, credential(:platform))
    assert {:ok, _} = request(InstallationOperator.authority(), @tenant, credential(:platform))
    key = %Principal{api_key_id: "key", tenant_key: @tenant, scopes: MapSet.new([:admin])}
    assert {:error, :provider_service_forbidden} = request(key, @tenant, credential(:platform))
  end

  test "checks each resolved credential for owner, status, provider and binding identity" do
    for value <- [
          credential(@other),
          %{
            credential(@tenant)
            | credential: %{credential(@tenant).credential | status: :revoked}
          },
          %{
            credential(@tenant)
            | credential: %{credential(@tenant).credential | name: "another"}
          },
          %{credential(@tenant) | payload: %{}}
        ] do
      assert {:error, :provider_credential_unavailable} = request(actor(), @tenant, value)
    end

    assert {:error, :provider_credential_unavailable} = request(actor(), @tenant, :missing)
  end

  test "re-resolves the connection after revocation rather than returning a previous catalog" do
    assert {:ok, _} = request(actor(), @tenant, credential(@tenant))
    assert {:error, :provider_credential_unavailable} = request(actor(), @tenant, :missing)
    assert_received {:resolved, @tenant, _, _}
    assert_received {:resolved, @tenant, _, _}
  end

  test "rejects invalid scope and query without leaking repository failures" do
    assert {:error, :invalid_voice_scope} =
             VoiceCatalog.request(
               actor(),
               @tenant,
               %{@scope | model: "unknown"},
               :describe,
               %{},
               options(credential(@tenant))
             )

    refute_received {:resolved, _, _, _}

    assert {:error, :invalid_voice_query} =
             VoiceCatalog.request(
               actor(),
               @tenant,
               @scope,
               :list,
               %{"search" => []},
               options(credential(@tenant))
             )

    assert {:error, :voice_catalog_unavailable} = request(actor(), @tenant, :crash)
  end

  def resolve({owner, result}, tenant, provider, name) do
    send(owner, {:resolved, tenant, provider, name})

    case result do
      :missing -> {:error, :not_found}
      :crash -> raise "private-sentinel"
      _ -> {:ok, result}
    end
  end

  defp request(actor, tenant, result),
    do: VoiceCatalog.request(actor, tenant, @scope, :list, %{}, options(result))

  defp options(result), do: [provider_credential_repository: {__MODULE__, {self(), result}}]

  defp credential(owner) do
    %ResolvedProviderCredential{
      credential: %ProviderCredential{
        id: "credential-1",
        tenant_key: ProviderCredential.owner_key(owner),
        owner: ProviderCredential.owner_tag(owner),
        provider: "morse_code_api",
        name: "speech",
        auth_kind: "api_key"
      },
      payload: %{"api_key" => "private-test-key"}
    }
  end

  defp actor(extra \\ []) do
    %UserPrincipal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["call_specs.read" | extra]),
      assigned_tenants: %{@tenant => :read},
      all_tenant_actions: MapSet.new()
    }
  end
end
