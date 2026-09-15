defmodule Vxpipe.Calls.Admissions do
  @moduledoc "Prepared-call and single-use participant admission workflows."

  alias Vxpipe.Calls.{
    AdmissionClaim,
    DefinitionCredentials,
    IssuedJoinToken,
    JoinToken,
    PreparedCall,
    PreparedCallFactory,
    Principal,
    PublicId,
    Repositories
  }

  @default_token_ttl_seconds 300

  @spec prepare(Principal.t(), String.t(), map(), keyword()) ::
          {:ok, PreparedCall.t(), IssuedJoinToken.t()} | {:error, term()}
  def prepare(principal, participant_key, initial_variables, options \\ [])

  def prepare(%Principal{} = principal, participant_key, initial_variables, options)
      when is_binary(participant_key) and is_map(initial_variables) do
    with :ok <- authorize(principal),
         {:ok, definition_repository} <-
           Repositories.fetch(options, :definition_repository),
         {:ok, call_repository} <- Repositories.fetch(options, :call_repository),
         {:ok, route} <-
           Repositories.call(definition_repository, :resolve_route, [
             principal.tenant_key,
             participant_key
           ]),
         {:ok, revision} <-
           Repositories.call(definition_repository, :fetch_revision, [
             principal.tenant_key,
             route.definition_id,
             route.definition_revision
           ]),
         {:ok, call} <- PreparedCallFactory.build(revision, initial_variables, :web, options),
         :ok <- entry_caller(route.participant_ref, call.entry_caller),
         {:ok, token_pair} <-
           build_token(call.plan, participant_key, route.participant_ref, options),
         {:ok, stored_call, _stored_token} <-
           DefinitionCredentials.with_active(revision, call.plan, options, fn ->
             Repositories.call(call_repository, :insert_prepared_call, [call, token_pair.stored])
           end) do
      {:ok, stored_call, token_pair.issued}
    end
  end

  def prepare(%Principal{}, _participant_key, _initial_variables, _options),
    do: {:error, :invalid_call_preparation}

  @spec fetch(String.t(), String.t(), keyword()) :: {:ok, PreparedCall.t()} | {:error, term()}
  def fetch(tenant_key, call_id, options \\ [])
      when is_binary(tenant_key) and is_binary(call_id) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :fetch_call, [tenant_key, call_id])
    end
  end

  @spec issue_token(Principal.t(), String.t(), String.t(), keyword()) ::
          {:ok, IssuedJoinToken.t()} | {:error, term()}
  def issue_token(%Principal{} = principal, call_id, participant_key, options \\ [])
      when is_binary(call_id) and is_binary(participant_key) do
    with :ok <- authorize(principal),
         {:ok, repository} <- Repositories.fetch(options, :call_repository),
         {:ok, call} <-
           Repositories.call(repository, :fetch_call, [principal.tenant_key, call_id]),
         {:ok, participant_ref} <- Map.fetch(call.participant_routes, participant_key),
         {:ok, token_pair} <- build_token(call.plan, participant_key, participant_ref, options),
         {:ok, _stored_token} <-
           Repositories.call(repository, :issue_join_token, [
             principal.tenant_key,
             call_id,
             participant_key,
             token_pair.stored
           ]) do
      {:ok, token_pair.issued}
    else
      :error -> {:error, :participant_not_found}
      {:error, _reason} = error -> error
    end
  end

  @spec claim_token(String.t(), map(), keyword()) ::
          {:ok, Vxpipe.Calls.AdmissionClaim.t()} | {:error, term()}
  def claim_token(secret, expected_scope, options \\ [])

  def claim_token(secret, expected_scope, options)
      when is_binary(secret) and is_map(expected_scope) do
    with :ok <- valid_scope(expected_scope),
         {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :claim_join_token, [
        token_digest(secret),
        expected_scope,
        now(options)
      ])
    end
  end

  def claim_token(_secret, _expected_scope, _options), do: {:error, :invalid_join_token}

  @spec release(AdmissionClaim.t(), keyword()) :: :ok | {:error, term()}
  def release(claim, options \\ [])

  def release(%AdmissionClaim{} = claim, options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :release_admission, [claim, now(options)])
    end
  end

  def release(_claim, _options), do: {:error, :invalid_admission}

  @spec mark_started(AdmissionClaim.t(), String.t(), DateTime.t(), keyword()) ::
          {:ok, PreparedCall.t()} | {:error, term()}
  def mark_started(claim, incarnation_id, started_at, options \\ [])

  def mark_started(%AdmissionClaim{} = claim, incarnation_id, %DateTime{} = started_at, options)
      when is_binary(incarnation_id) and byte_size(incarnation_id) > 0 do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :mark_call_started, [claim, incarnation_id, started_at])
    end
  end

  def mark_started(_claim, _incarnation_id, _started_at, _options),
    do: {:error, :invalid_call_start}

  @spec mark_failed(AdmissionClaim.t(), atom(), keyword()) ::
          {:ok, PreparedCall.t()} | {:error, term()}
  def mark_failed(claim, reason, options \\ [])

  def mark_failed(%AdmissionClaim{} = claim, reason, options)
      when reason in [:room_start_failed, :session_start_failed, :startup_unknown] do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      Repositories.call(repository, :mark_call_failed, [claim, reason, now(options)])
    end
  end

  def mark_failed(_claim, _reason, _options), do: {:error, :invalid_call_failure}

  defp build_token(plan, participant_key, participant_ref, options) do
    with {:ok, ttl_seconds} <- token_ttl(options),
         secret when is_binary(secret) and byte_size(secret) > 0 <-
           generator(options, :join_token_generator, &PublicId.join_token/0).() do
      issued_at = now(options)

      stored = %JoinToken{
        id: generated_id(options, :token_id_generator),
        tenant_key: plan.tenant_id,
        call_id: plan.call_id,
        participant_key: participant_key,
        participant_ref: participant_ref,
        digest: token_digest(secret),
        issued_at: issued_at,
        expires_at: DateTime.add(issued_at, ttl_seconds, :second),
        consumed_at: nil
      }

      issued = %IssuedJoinToken{
        id: stored.id,
        secret: secret,
        tenant_key: stored.tenant_key,
        call_id: stored.call_id,
        participant_key: stored.participant_key,
        participant_ref: stored.participant_ref,
        issued_at: stored.issued_at,
        expires_at: stored.expires_at
      }

      {:ok, %{stored: stored, issued: issued}}
    else
      _invalid -> {:error, :invalid_join_token_configuration}
    end
  end

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :not_authorized}
  end

  defp entry_caller(participant_ref, participant_ref), do: :ok
  defp entry_caller(_participant_ref, _entry_caller), do: {:error, :participant_not_entry_caller}

  defp valid_scope(%{
         tenant_key: tenant_key,
         call_id: call_id,
         participant_key: participant_key
       })
       when is_binary(tenant_key) and is_binary(call_id) and is_binary(participant_key),
       do: :ok

  defp valid_scope(_invalid), do: {:error, :invalid_join_scope}

  defp token_ttl(options) do
    case Keyword.get(options, :join_token_ttl_seconds, @default_token_ttl_seconds) do
      seconds when is_integer(seconds) and seconds >= @default_token_ttl_seconds -> {:ok, seconds}
      _invalid -> {:error, :invalid_join_token_ttl}
    end
  end

  defp token_digest(secret), do: :crypto.hash(:sha256, secret)
  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

  defp generated_id(options, key) do
    options
    |> generator(key, &PublicId.uuid/0)
    |> then(& &1.())
  end

  defp generator(options, key, default), do: Keyword.get(options, key, default)
end
