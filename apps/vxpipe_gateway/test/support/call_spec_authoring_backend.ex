defmodule Vxpipe.Gateway.TestCallSpecAuthoringBackend do
  alias Vxpipe.Calls.{CallSpecRevision, InstallationOperator, Principal}
  @tenant "AAAAAAAAAAAAAAAA"

  def authenticate(_context, :operator, _tenant, "operator-key"),
    do: {:ok, %InstallationOperator{grant: :installation_operator, api_key_id: "operator-id"}}

  def authenticate(_context, :tenant, @tenant, "tenant-key"),
    do:
      {:ok,
       %Principal{tenant_key: @tenant, api_key_id: "tenant-id", scopes: MapSet.new([:admin])}}

  def authenticate(_context, :tenant, @tenant, "calls-only"), do: {:error, :insufficient_scope}
  def authenticate(_context, _scope, _tenant, _key), do: {:error, :invalid_api_key}

  def providers({observer, result}, author, tenant, capability) do
    send(observer, {:providers, author, tenant, capability})
    if result == :crash, do: raise("private-sentinel")
    result
  end

  def models({observer, result}, author, tenant, provider, capability) do
    send(observer, {:models, author, tenant, provider, capability})
    result
  end

  def save({observer, result}, author, tenant, source, id) do
    send(observer, {:save, author, tenant, source, id})
    if result == :crash, do: raise("private backend failure")
    result || {:ok, revision(tenant, id || "generated-spec", if(id, do: 2, else: 1))}
  end

  def publish({observer, result}, author, tenant, id, version) do
    send(observer, {:publish, author, tenant, id, version})
    result || {:ok, %{revision(tenant, id, version) | published_at: ~U[2026-09-19 01:00:00Z]}}
  end

  defp revision(tenant, id, version) do
    %CallSpecRevision{
      tenant_key: tenant,
      call_spec_id: id,
      revision: version,
      schema_version: "20260915.01",
      source: %{private: "must-not-echo"},
      source_digest: "digest",
      compiled_metadata: %{private: "must-not-echo"},
      validation_errors: [%{"reason" => "must-not-echo"}],
      routes: [],
      telephony_routes: [],
      published_at: nil,
      inserted_at: ~U[2026-09-19 01:00:00Z]
    }
  end
end
