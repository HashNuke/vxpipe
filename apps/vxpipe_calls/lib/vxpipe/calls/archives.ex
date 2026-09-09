defmodule Vxpipe.Calls.Archives do
  @moduledoc "Database-neutral private call-history workflows."

  alias Vxpipe.Calls.{Principal, Repositories, VariableSnapshot}

  @spec store_variable_snapshot(VariableSnapshot.t(), keyword()) ::
          {:ok, VariableSnapshot.t()} | {:error, term()}
  def store_variable_snapshot(%VariableSnapshot{} = snapshot, options) when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :archive_repository) do
      Repositories.call(repository, :store_variable_snapshot, [snapshot])
    end
  end

  def store_variable_snapshot(_snapshot, _options), do: {:error, :invalid_variable_snapshot}

  @spec fetch_variable_snapshots(Principal.t(), String.t(), keyword()) ::
          {:ok, Vxpipe.Calls.VariableSnapshotHistory.t()} | {:error, term()}
  def fetch_variable_snapshots(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with :ok <- authorize(principal),
         {:ok, repository} <- Repositories.fetch(options, :archive_repository) do
      Repositories.call(repository, :fetch_variable_snapshots, [principal.tenant_key, call_id])
    end
  end

  def fetch_variable_snapshots(_principal, _call_id, _options),
    do: {:error, :invalid_archive_request}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :insufficient_scope}
  end
end
