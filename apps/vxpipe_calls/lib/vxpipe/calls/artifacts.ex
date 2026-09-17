defmodule Vxpipe.Calls.Artifacts do
  @moduledoc "Database-neutral workflows for terminal call-artifact metadata."

  alias Vxpipe.Calls.{CallArtifact, CallReadAccess, PublicationTriggers, Repositories}

  @spec store(CallArtifact.t(), keyword()) :: {:ok, CallArtifact.t()} | {:error, term()}
  def store(%CallArtifact{} = artifact, options) when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :artifact_repository),
         {:ok, stored} <- Repositories.call(repository, :store_call_artifact, [artifact]) do
      _result = PublicationTriggers.request(stored.tenant_key, stored.call_id, options)
      {:ok, stored}
    end
  end

  def store(_artifact, _options), do: {:error, :invalid_call_artifact}

  @spec fetch(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, [CallArtifact.t()]} | {:error, term()}
  def fetch(authority, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with {:ok, tenant_key} <- CallReadAccess.tenant_key(authority, :invalid_artifact_request),
         {:ok, repository} <- Repositories.fetch(options, :artifact_repository) do
      Repositories.call(repository, :fetch_call_artifacts, [tenant_key, call_id])
    end
  end

  def fetch(_principal, _call_id, _options), do: {:error, :invalid_artifact_request}

  @spec fetch_one(CallReadAccess.authority(), String.t(), String.t(), keyword()) ::
          {:ok, CallArtifact.t()} | {:error, term()}
  def fetch_one(authority, call_id, artifact_id, options)
      when is_binary(call_id) and is_binary(artifact_id) and is_list(options) do
    with {:ok, tenant_key} <- CallReadAccess.tenant_key(authority, :invalid_artifact_request),
         {:ok, repository} <- Repositories.fetch(options, :artifact_repository) do
      Repositories.call(repository, :fetch_call_artifact, [
        tenant_key,
        call_id,
        artifact_id
      ])
    end
  end

  def fetch_one(_principal, _call_id, _artifact_id, _options),
    do: {:error, :invalid_artifact_request}

end
