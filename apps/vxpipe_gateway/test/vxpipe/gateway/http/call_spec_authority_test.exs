defmodule Vxpipe.Gateway.HTTP.CallSpecAuthorityTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    ProviderCredential,
    ResolvedProviderCredential,
    TestMemoryRepository
  }

  alias Vxpipe.Gateway.CallSpecAuthoring
  alias Vxpipe.Gateway.HTTP.Endpoint

  @platform "vxpk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @legacy "vxop_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {__MODULE__, repository},
      provider_credential_repository: {__MODULE__, nil},
      access_key_repository: {__MODULE__, nil},
      operator_api_key_repository: {__MODULE__, nil},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Canonical authority", [:admin], options)
    {:ok, other, foreign} = Administration.bootstrap_tenant("Other", [:admin], options)

    endpoint =
      Endpoint.init(call_spec_authoring: [enabled: true, backend: {CallSpecAuthoring, options}])

    %{
      options: options,
      endpoint: endpoint,
      tenant: tenant,
      key: key,
      other: other,
      foreign: foreign,
      repository: repository
    }
  end

  test "canonical writes preserve platform-service authority and tenant writes cannot store that source",
       ctx do
    path = "/api/tenants/#{ctx.tenant.key}/call-specs"
    denied = request(ctx, :post, path, ctx.key.secret)
    assert denied.status == 403
    assert JSON.decode!(denied.resp_body)["error"]["code"] == "provider_service_forbidden"
    refute_received {:revision_inserted, _}

    created = request(ctx, :post, path, @platform)
    assert created.status == 201
    id = JSON.decode!(created.resp_body)["call_spec"]["call_spec_id"]
    assert_received {:revision_inserted, 1}
    assert_received {:active_credentials, [%{provider: "google"} = requirement]}
    refute Map.has_key?(requirement, :allowed_owner)

    assert request(ctx, :put, path <> "/" <> id, ctx.key.secret).status == 403
    refute_received {:revision_inserted, _}
    assert request(ctx, :put, path <> "/" <> id, @platform).status == 201
    assert_received {:revision_inserted, 2}

    assert {:ok, first} =
             TestMemoryRepository.fetch_revision(ctx.repository, ctx.tenant.key, id, 1)

    assert first.source == source()
  end

  test "canonical authentication returns the original platform actor and rejects denied keys",
       ctx do
    assert {:ok,
            %InstallationOperator{credential_kind: :platform_api_key, api_key_id: "platform-key"}} =
             CallSpecAuthoring.authenticate(ctx.options, :tenant, ctx.tenant.key, @platform)

    {:ok, calls} =
      Administration.issue_api_key(ctx.tenant.key, "Calls only", [:calls], ctx.options)

    assert {:error, :insufficient_scope} =
             CallSpecAuthoring.authenticate(ctx.options, :tenant, ctx.tenant.key, calls.secret)

    assert {:error, :tenant_access_forbidden} =
             CallSpecAuthoring.authenticate(
               ctx.options,
               :tenant,
               ctx.tenant.key,
               ctx.foreign.secret
             )

    assert {:error, :invalid_api_key} =
             CallSpecAuthoring.authenticate(ctx.options, :tenant, ctx.tenant.key, @legacy)

    assert {:ok, %InstallationOperator{credential_kind: :legacy_operator_api_key}} =
             CallSpecAuthoring.authenticate(ctx.options, :operator, ctx.tenant.key, @legacy)

    refute_received {:revision_inserted, _}
  end

  def authenticate_platform(_context, digest) do
    if digest == :crypto.hash(:sha256, @platform),
      do: {:ok, "platform-key"},
      else: {:error, :invalid_api_key}
  end

  def fetch(_context, digest) do
    if digest == :crypto.hash(:sha256, @legacy),
      do: {:ok, %{id: "legacy-key", revoked_at: nil}},
      else: {:error, :not_found}
  end

  def resolve(_context, _tenant, "google", "default") do
    {:ok,
     %ResolvedProviderCredential{
       credential: %ProviderCredential{
         id: "platform-service",
         tenant_key: nil,
         owner: :platform,
         provider: "google",
         name: "default",
         auth_kind: "api_key"
       },
       payload: %{"api_key" => "synthetic-platform"}
     }}
  end

  def with_active(_context, _tenant, requirements, operation) do
    send(self(), {:active_credentials, requirements})
    operation.()
  end

  defdelegate allocate_id(repository), to: TestMemoryRepository
  defdelegate next_revision(repository, tenant, id), to: TestMemoryRepository
  defdelegate fetch_revision(repository, tenant, id, revision), to: TestMemoryRepository

  def insert_revision(repository, tenant, revision, routes) do
    send(self(), {:revision_inserted, revision.revision})
    TestMemoryRepository.insert_revision(repository, tenant, revision, routes)
  end

  defp request(ctx, method, path, secret) do
    conn(method, path, JSON.encode!(%{"source" => source()}))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> secret)
    |> Endpoint.call(ctx.endpoint)
  end

  defp source do
    %{
      "schema_version" => "20261004.01",
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "defaults" => %{
        "capabilities" => %{
          "model_inference" => %{"provider" => "google", "model" => "gemini-2.5-flash"}
        }
      },
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }
  end
end
