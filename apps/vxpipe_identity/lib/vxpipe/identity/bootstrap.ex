defmodule Vxpipe.Identity.Bootstrap do
  @moduledoc """
  First-Superadmin setup. Fresh installs trust the first visitor; upgraded
  databases require a trusted single-use local setup proof consumed atomically.
  """

  alias Vxpipe.Identity.{Email, Password, RateLimit}

  @spec status(map()) ::
          {:ok, :pending_first_run | :pending_operator_proof | :complete} | {:error, term()}
  def status(deps) do
    installations = Map.fetch!(deps, :installations)

    case installations.fetch() do
      {:ok, %{setup_completed_at: nil, mode: :first_run}} ->
        {:ok, :pending_first_run}

      {:ok, %{setup_completed_at: nil, mode: :operator_required}} ->
        {:ok, :pending_operator_proof}

      {:ok, %{setup_completed_at: %DateTime{}}} ->
        {:ok, :complete}

      {:ok, _} ->
        {:error, :corrupt}

      error ->
        error
    end
  end

  @spec complete_first_run(map(), String.t(), String.t(), String.t(), map()) ::
          {:ok, %{token: String.t(), user: map()}} | {:error, term()}
  def complete_first_run(deps, email, password, confirmation, opts \\ %{}) do
    installations = Map.fetch!(deps, :installations)
    hasher = Map.fetch!(deps, :hasher)
    tokens = Map.get(deps, :tokens, Vxpipe.Identity.Tokens)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)
    attempts = Map.get(deps, :attempts)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)
    now = clock.utc_now()
    address = client_address(opts)

    # Durable audit lives inside the atomic installation transaction
    # (IdentityInstallationStore appends setup_completed before commit), so no
    # outer append here: an outer failure must never mask a committed setup.
    with {:ok, normalized} <- Email.normalize(email),
         :ok <- check_bootstrap_rate(attempts, normalized, address, now),
         :ok <- Password.confirm(password, confirmation),
         {:ok, hash} <- hasher.hash(password),
         {:ok, %{token: token, digest: digest}} <- tokens.generate(),
         {:ok, result} <-
           installations.complete_first_run(%{
             email: String.trim(email),
             normalized_email: normalized,
             password_hash: hash,
             user_public_id: uuid.generate(),
             session_public_id: uuid.generate(),
             session_digest: digest,
             session_expires_at: Vxpipe.Identity.Tokens.expiry(now)
           }) do
      {:ok, %{token: token, user: Map.drop(result.user, [:password_hash])}}
    else
      {:error, :invalid_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :proof_required} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :expired_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :already_completed} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      error ->
        error
    end
  end

  @spec complete_with_proof(map(), String.t(), String.t(), String.t(), String.t(), map()) ::
          {:ok, %{token: String.t(), user: map()}} | {:error, term()}
  def complete_with_proof(deps, proof, email, password, confirmation, opts \\ %{}) do
    installations = Map.fetch!(deps, :installations)
    hasher = Map.fetch!(deps, :hasher)
    tokens = Map.get(deps, :tokens, Vxpipe.Identity.Tokens)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)
    attempts = Map.get(deps, :attempts)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)
    now = clock.utc_now()
    address = client_address(opts)

    # Atomic store operation audits setup completion; no outer append.
    with {:ok, normalized} <- Email.normalize(email),
         :ok <- check_bootstrap_rate(attempts, normalized, address, now),
         :ok <- Password.confirm(password, confirmation),
         {:ok, hash} <- hasher.hash(password),
         {:ok, %{token: token, digest: digest}} <- tokens.generate(),
         {:ok, result} <-
           installations.consume_setup_proof(proof, %{
             email: String.trim(email),
             normalized_email: normalized,
             password_hash: hash,
             user_public_id: uuid.generate(),
             session_public_id: uuid.generate(),
             session_digest: digest,
             session_expires_at: Vxpipe.Identity.Tokens.expiry(now)
           }) do
      {:ok, %{token: token, user: Map.drop(result.user, [:password_hash])}}
    else
      {:error, :invalid_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :proof_required} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :expired_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :already_completed} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      error ->
        error
    end
  end

  @spec issue_setup_proof(map()) :: {:ok, %{proof: String.t()}} | {:error, term()}
  def issue_setup_proof(deps) do
    installations = Map.fetch!(deps, :installations)
    installations.issue_setup_proof(900)
  end

  @spec issue_recovery_proof(map()) :: {:ok, %{proof: String.t()}} | {:error, term()}
  def issue_recovery_proof(deps) do
    installations = Map.fetch!(deps, :installations)
    installations.issue_recovery_proof(900)
  end

  @spec recover_with_proof(map(), String.t(), String.t(), String.t(), String.t(), map()) ::
          {:ok, %{token: String.t(), user: map()}} | {:error, term()}
  def recover_with_proof(deps, proof, email, password, confirmation, opts \\ %{}) do
    installations = Map.fetch!(deps, :installations)
    hasher = Map.fetch!(deps, :hasher)
    tokens = Map.get(deps, :tokens, Vxpipe.Identity.Tokens)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)
    attempts = Map.get(deps, :attempts)
    clock = Map.get(deps, :clock, Vxpipe.Identity.Clock)
    now = clock.utc_now()
    address = client_address(opts)

    # Atomic store operation audits recovery; no outer append.
    with {:ok, normalized} <- Email.normalize(email),
         :ok <- check_bootstrap_rate(attempts, normalized, address, now),
         :ok <- Password.confirm(password, confirmation),
         {:ok, hash} <- hasher.hash(password),
         {:ok, %{token: token, digest: digest}} <- tokens.generate(),
         {:ok, result} <-
           installations.consume_recovery_proof(proof, %{
             email: String.trim(email),
             normalized_email: normalized,
             password_hash: hash,
             session_public_id: uuid.generate(),
             session_digest: digest,
             session_expires_at: Vxpipe.Identity.Tokens.expiry(now)
           }) do
      {:ok, %{token: token, user: Map.drop(result.user, [:password_hash])}}
    else
      {:error, :invalid_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :expired_proof} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      {:error, :not_complete} = error ->
        _ = record_bootstrap_attempt(attempts, safe_account(email), address, now)
        error

      error ->
        error
    end
  end

  defp client_address(opts) when is_map(opts) do
    Map.get(opts, :client_address, Map.get(opts, "client_address", "local"))
  end

  defp client_address(opts) when is_list(opts) do
    Keyword.get(opts, :client_address, "local")
  end

  defp client_address(_), do: "local"

  defp check_bootstrap_rate(nil, _account, _address, _now), do: :ok

  defp check_bootstrap_rate(attempts, account, address, now) do
    case attempts.recent(account, address, now, RateLimit.window_seconds()) do
      {:ok, %{account: a, address: b}} -> RateLimit.allowed?(a, b, now)
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  defp record_bootstrap_attempt(nil, _account, _address, _now), do: :ok

  defp record_bootstrap_attempt(attempts, account, address, now) do
    _ = attempts.record(account, address, now)
    :ok
  end

  defp safe_account(email) when is_binary(email) do
    case Email.normalize(email) do
      {:ok, normalized} -> normalized
      _ -> "invalid"
    end
  end

  defp safe_account(_), do: "invalid"
end
