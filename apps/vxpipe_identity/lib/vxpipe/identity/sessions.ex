defmodule Vxpipe.Identity.Sessions do
  @moduledoc "Database-backed opaque sessions with 12-hour absolute expiry."

  alias Vxpipe.Identity.{Email, RateLimit, Tokens}

  @spec login(map(), String.t(), String.t(), String.t()) ::
          {:ok, %{token: String.t(), session: map(), user: map()}} | {:error, term()}
  def login(deps, email, password, client_address) do
    users = Map.fetch!(deps, :users)
    session_store = Map.fetch!(deps, :sessions)
    attempts = Map.get(deps, :attempts)
    hasher = Map.fetch!(deps, :hasher)
    tokens = Map.get(deps, :tokens, Tokens)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)

    now = clock.utc_now()

    with {:ok, normalized} <- Email.normalize(email),
         :ok <- check_rate(deps, attempts, normalized, client_address, now),
         :ok <- password_shape(password),
         {:ok, user} <- fetch_user(users, normalized),
         :ok <- check_enabled(user),
         true <- hasher.verify(password, user.password_hash) || {:error, :invalid_credentials},
         {:ok, %{token: token, digest: digest}} <- tokens.generate(),
         {:ok, session} <-
           session_store.create(%{
             public_id: uuid.generate(),
             user_public_id: user.public_id,
             digest: digest,
             expires_at: Tokens.expiry(now)
           }),
         :ok <- append_login_audit(audit, session_store, digest, user, now) do
      {:ok,
       %{
         token: token,
         session: Map.drop(session, [:digest]),
         user: Map.drop(user, [:password_hash])
       }}
    else
      {:error, :invalid_credentials} = error ->
        _ = record_attempt(attempts, safe_account(email), client_address, now)
        error

      {:error, :not_found} ->
        _ = record_attempt(attempts, safe_account(email), client_address, now)
        {:error, :invalid_credentials}

      error ->
        error
    end
  end

  @spec logout(map(), String.t()) :: :ok | {:error, term()}
  def logout(deps, token) do
    session_store = Map.fetch!(deps, :sessions)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)

    digest = Tokens.digest(token)

    case session_store.fetch_valid(digest, clock.utc_now()) do
      {:ok, session} ->
        with :ok <- session_store.revoke_one(digest, clock.utc_now()),
             :ok <-
               audit.append(%{
                 action: "logout",
                 actor_user_public_id: session.user_public_id,
                 summary: %{}
               }) do
          :ok
        end

      {:error, :not_found} ->
        :ok

      {:error, :expired} ->
        :ok

      {:error, :revoked} ->
        :ok

      {:error, :disabled} ->
        case session_store.revoke_one(digest, clock.utc_now()) do
          :ok -> :ok
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec authenticate(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def authenticate(deps, token) do
    session_store = Map.fetch!(deps, :sessions)
    users = Map.fetch!(deps, :users)
    roles = Map.fetch!(deps, :roles)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)

    digest = Tokens.digest(token)

    with {:ok, session} <- session_store.fetch_valid(digest, clock.utc_now()),
         {:ok, user} <- users.fetch_by_public_id(session.user_public_id),
         :ok <- check_enabled(user),
         {:ok, role} <- roles.fetch(user.role_public_id),
         {:ok, principal} <- Vxpipe.Identity.Principal.for_session(user, role, session) do
      {:ok, principal}
    end
  end

  defp fetch_user(users, normalized) do
    case users.fetch_by_email(normalized) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  # Any non-string password is an ordinary counted failure, never a hasher crash.
  defp password_shape(password) when is_binary(password), do: :ok
  defp password_shape(_password), do: {:error, :invalid_credentials}

  defp check_enabled(%{disabled_at: nil}), do: :ok
  defp check_enabled(%{"disabled_at" => nil}), do: :ok
  defp check_enabled(_), do: {:error, :disabled}

  defp check_rate(_deps, nil, _account, _address, _now), do: :ok

  defp check_rate(_deps, attempts, account, address, now) do
    case attempts.recent(account, address, now, RateLimit.window_seconds()) do
      {:ok, %{account: a, address: b}} -> RateLimit.allowed?(a, b, now)
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  defp record_attempt(nil, _account, _address, _now), do: :ok

  defp record_attempt(attempts, account, address, now) do
    _ = attempts.record(account, address, now)
    :ok
  end

  defp append_login_audit(audit, session_store, digest, user, now) do
    case audit.append(%{action: "login", actor_user_public_id: user.public_id, summary: %{}}) do
      :ok ->
        :ok

      error ->
        _ = session_store.revoke_one(digest, now)
        error
    end
  end

  defp safe_account(email) when is_binary(email) do
    case Email.normalize(email) do
      {:ok, normalized} -> normalized
      _ -> "invalid"
    end
  end
end
