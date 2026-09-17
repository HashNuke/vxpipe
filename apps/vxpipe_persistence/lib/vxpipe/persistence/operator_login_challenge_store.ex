defmodule Vxpipe.Persistence.OperatorLoginChallengeStore do
  @moduledoc "PostgreSQL adapter for one-time installation-operator login challenges."
  @behaviour Vxpipe.Calls.OperatorLoginChallengeRepository

  import Ecto.Query

  alias Vxpipe.Calls.OperatorLoginChallenge, as: Challenge
  alias Vxpipe.Persistence.Schema.OperatorLoginChallenge, as: StoredChallenge

  @maximum_failed_attempts 5
  @private_query_options [log: false, telemetry_event: nil]

  @impl true
  def insert(context, %Challenge{} = challenge) do
    repo = Keyword.fetch!(context, :repo)
    attributes = Map.from_struct(challenge)

    case repo.insert(
           StoredChallenge.changeset(%StoredChallenge{}, attributes),
           @private_query_options
         ) do
      {:ok, _stored} -> {:ok, challenge}
      {:error, _changeset} -> {:error, :operator_login_challenge_write_failed}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :repository_unavailable}
  end

  @impl true
  def consume(context, token_digest, submitted_verifier) do
    repo = Keyword.fetch!(context, :repo)

    case repo.transaction(
           fn -> consume_locked(context, token_digest, submitted_verifier) end,
           @private_query_options
         ) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :repository_unavailable}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :repository_unavailable}
  end

  defp consume_locked(context, token_digest, submitted_verifier) do
    repo = Keyword.fetch!(context, :repo)

    stored =
      repo.one(
        from(challenge in StoredChallenge,
          where: challenge.token_digest == ^token_digest,
          lock: "FOR UPDATE"
        ),
        @private_query_options
      )

    now = current_time(context)

    cond do
      invalid?(stored, now) ->
        {:error, :invalid_operator_login_challenge}

      :crypto.hash_equals(stored.code_verifier, submitted_verifier) ->
        update_consumed(repo, stored, now)

      true ->
        update_failed(repo, stored)
    end
  end

  defp invalid?(nil, _now), do: true

  defp invalid?(stored, now) do
    not is_nil(stored.consumed_at) or
      stored.failed_attempts >= @maximum_failed_attempts or
      DateTime.compare(now, stored.expires_at) != :lt
  end

  defp update_consumed(repo, stored, now) do
    case repo.update(StoredChallenge.consume_changeset(stored, now), @private_query_options) do
      {:ok, _updated} -> :ok
      {:error, _changeset} -> repo.rollback(:operator_login_challenge_write_failed)
    end
  end

  defp update_failed(repo, stored) do
    case repo.update(StoredChallenge.fail_changeset(stored), @private_query_options) do
      {:ok, _updated} -> {:error, :invalid_operator_login_challenge}
      {:error, _changeset} -> repo.rollback(:operator_login_challenge_write_failed)
    end
  end

  defp current_time(context) do
    context
    |> Keyword.get(:now, &DateTime.utc_now/0)
    |> then(fn clock -> clock.() end)
  end

  defp repository_error(%DBConnection.ConnectionError{}, _trace),
    do: {:error, :repository_unavailable}

  defp repository_error(%Postgrex.Error{}, _trace), do: {:error, :repository_unavailable}

  defp repository_error(%RuntimeError{}, [{Ecto.Repo.Registry, :lookup, _, _} | _]),
    do: {:error, :repository_unavailable}

  defp repository_error(%ArgumentError{}, [
         {:ets, :lookup_element, [Ecto.Repo.Registry | _], _} | _
       ]),
       do: {:error, :repository_unavailable}

  defp repository_error(error, trace), do: reraise(error, trace)
end
