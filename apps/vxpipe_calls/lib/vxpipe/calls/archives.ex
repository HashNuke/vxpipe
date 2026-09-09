defmodule Vxpipe.Calls.Archives do
  @moduledoc "Database-neutral private call-history workflows."

  alias Vxpipe.Calls.{CallFact, CallHistory, Principal, Repositories, VariableSnapshot}

  @spec store_call_fact(CallFact.t(), keyword()) ::
          {:ok, CallFact.t()} | {:error, term()}
  def store_call_fact(%CallFact{} = fact, options) when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :archive_repository) do
      Repositories.call(repository, :store_call_fact, [fact])
    end
  end

  def store_call_fact(_fact, _options), do: {:error, :invalid_call_fact}

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

  @spec fetch_call_facts(Principal.t(), String.t(), keyword()) ::
          {:ok, [CallFact.t()]} | {:error, term()}
  def fetch_call_facts(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with :ok <- authorize(principal),
         {:ok, repository} <- Repositories.fetch(options, :archive_repository) do
      Repositories.call(repository, :fetch_call_facts, [principal.tenant_key, call_id])
    end
  end

  def fetch_call_facts(_principal, _call_id, _options),
    do: {:error, :invalid_archive_request}

  @spec fetch_call_history(Principal.t(), String.t(), keyword()) ::
          {:ok, CallHistory.t()} | {:error, term()}
  def fetch_call_history(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with :ok <- authorize(principal),
         {:ok, repository} <- Repositories.fetch(options, :archive_repository),
         {:ok, facts} <-
           Repositories.call(repository, :fetch_call_facts, [principal.tenant_key, call_id]),
         {:ok, variable_snapshots} <-
           Repositories.call(repository, :fetch_variable_snapshots, [
             principal.tenant_key,
             call_id
           ]) do
      {:ok, CallHistory.new(facts, variable_snapshots)}
    end
  end

  def fetch_call_history(_principal, _call_id, _options),
    do: {:error, :invalid_archive_request}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :insufficient_scope}
  end
end
