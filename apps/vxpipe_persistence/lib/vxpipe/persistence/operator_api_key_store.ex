defmodule Vxpipe.Persistence.OperatorApiKeyStore do
  @moduledoc "Hash-only installation-key persistence with atomic bootstrap and replacement."
  @behaviour Vxpipe.Calls.OperatorApiKeyRepository
  import Ecto.Query
  alias Vxpipe.Persistence.Schema.OperatorApiKey

  @private [log: false, telemetry_event: nil]

  @impl true
  def issue(repo, record, mode) when mode in [:bootstrap, :replace] do
    safely(fn ->
      repo.transaction(
        fn ->
          # Rare trusted writes serialize even when the table is initially empty.
          # ACCESS SHARE authentication reads remain available during replacement.
          repo.query!("LOCK TABLE operator_api_keys IN EXCLUSIVE MODE", [], @private)

          if mode == :bootstrap and repo.exists?(OperatorApiKey, @private),
            do: repo.rollback(:operator_key_already_initialized)

          if mode == :replace do
            repo.update_all(
              from(k in OperatorApiKey, where: is_nil(k.revoked_at)),
              [set: [revoked_at: record.inserted_at, updated_at: record.inserted_at]],
              @private
            )
          end

          attributes = %{
            public_id: record.id,
            digest: record.digest,
            inserted_at: record.inserted_at,
            revoked_at: nil
          }

          case repo.insert(OperatorApiKey.changeset(%OperatorApiKey{}, attributes), @private) do
            {:ok, stored} -> to_key_record(stored)
            {:error, _changeset} -> repo.rollback(:operator_key_conflict)
          end
        end,
        @private
      )
    end)
  end

  @impl true
  def fetch(repo, digest) do
    safely(fn ->
      case repo.get_by(OperatorApiKey, [digest: digest], @private) do
        nil -> {:error, :not_found}
        stored -> {:ok, to_key_record(stored)}
      end
    end)
  end

  @impl true
  def revoke(repo, id, now) do
    safely(fn ->
      repo.transaction(
        fn ->
          repo.query!("LOCK TABLE operator_api_keys IN EXCLUSIVE MODE", [], @private)

          stored =
            repo.get_by(OperatorApiKey, [public_id: id], @private) || repo.rollback(:not_found)

          case repo.update(
                 Ecto.Changeset.change(stored, revoked_at: stored.revoked_at || now),
                 @private
               ) do
            {:ok, updated} -> to_key_record(updated)
            {:error, _changeset} -> repo.rollback(:operator_key_write_failed)
          end
        end,
        @private
      )
    end)
  end

  defp to_key_record(stored),
    do: %{
      id: stored.public_id,
      digest: stored.digest,
      inserted_at: stored.inserted_at,
      revoked_at: stored.revoked_at
    }

  defp safely(operation) do
    operation.()
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :repository_unavailable}
  end

  defp repository_error(%DBConnection.ConnectionError{}, _trace),
    do: {:error, :repository_unavailable}

  defp repository_error(%Postgrex.Error{}, _trace), do: {:error, :repository_unavailable}

  defp repository_error(%RuntimeError{}, [{Ecto.Repo.Registry, :lookup, _, _} | _]),
    do: {:error, :repository_unavailable}

  defp repository_error(error, trace), do: reraise(error, trace)
end
