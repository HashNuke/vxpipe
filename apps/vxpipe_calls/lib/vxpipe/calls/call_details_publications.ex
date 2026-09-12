defmodule Vxpipe.Calls.CallDetailsPublications do
  @moduledoc "Database-neutral lifecycle operations for call-details publication records."

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsSnapshot, Repositories}

  @spec reserve(String.t(), String.t(), CallDetailsSnapshot.t(), keyword()) ::
          {:ok, Vxpipe.Calls.CallDetailsPublication.t(), :created | :existing} | {:error, term()}
  def reserve(tenant_key, call_id, %CallDetailsSnapshot{} = snapshot, options)
      when is_binary(tenant_key) and is_binary(call_id) and is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :publication_repository) do
      Repositories.call(repository, :reserve, [tenant_key, call_id, snapshot])
    end
  end

  def reserve(_tenant_key, _call_id, _snapshot, _options),
    do: {:error, :invalid_call_details_publication}

  @spec mark_published(String.t(), String.t(), String.t(), CallDetailsObject.t(), keyword()) ::
          {:ok, Vxpipe.Calls.CallDetailsPublication.t()} | {:error, term()}
  def mark_published(tenant_key, call_id, publication_id, %CallDetailsObject{} = object, options)
      when is_binary(tenant_key) and is_binary(call_id) and is_binary(publication_id) and
             is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :publication_repository) do
      Repositories.call(repository, :mark_published, [tenant_key, call_id, publication_id, object])
    end
  end

  def mark_published(_tenant_key, _call_id, _publication_id, _object, _options),
    do: {:error, :invalid_call_details_publication}
end
