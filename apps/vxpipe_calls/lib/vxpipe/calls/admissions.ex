defmodule Vxpipe.Calls.Admissions do
  @moduledoc "Prepared-call and single-use participant admission workflows."

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, ResolvedCallPlan}

  alias Vxpipe.Calls.{
    IssuedJoinToken,
    JoinToken,
    PreparedCall,
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
         {:ok, definition} <-
           CallDefinition.new(revision.source,
             resource_id: revision.definition_id,
             revision: revision.revision
           ),
         :ok <- entry_caller(route.participant_ref, definition.entry_caller),
         {:ok, plan} <- compile_plan(definition, principal, initial_variables, options),
         {:ok, token_pair} <- build_token(plan, participant_key, route.participant_ref, options),
         call <- prepared_call(plan, revision.routes, initial_variables, options),
         {:ok, stored_call, _stored_token} <-
           Repositories.call(call_repository, :insert_prepared_call, [call, token_pair.stored]) do
      {:ok, stored_call, token_pair.issued}
    end
  end

  def prepare(%Principal{}, _participant_key, _initial_variables, _options),
    do: {:error, :invalid_call_preparation}

  @spec fetch(String.t(), String.t(), keyword()) :: {:ok, PreparedCall.t()} | {:error, term()}
  def fetch(tenant_key, call_id, options \\ []) when is_binary(tenant_key) and is_binary(call_id) do
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

  defp compile_plan(definition, principal, initial_variables, options) do
    invocation_input = %{
      call_definition: %{id: definition.resource_id, revision: definition.revision},
      initial_variables: initial_variables,
      transport: %{type: "web"}
    }

    with {:ok, invocation} <-
           CallInvocation.new(invocation_input,
             tenant_id: principal.tenant_key,
             actor_id: generated_id(options, :actor_id_generator),
             call_id: generated_id(options, :call_id_generator),
             room_id: generated_id(options, :room_id_generator)
           ),
         {:ok, registries} <- registries(options) do
      DefinitionCompiler.compile(definition, invocation, registries)
    end
  end

  defp prepared_call(%ResolvedCallPlan{} = plan, routes, initial_variables, options) do
    %PreparedCall{
      id: plan.call_id,
      tenant_key: plan.tenant_id,
      definition_id: plan.definition_id,
      definition_revision: plan.definition_revision,
      schema_version: plan.schema_version,
      participant_routes: Map.new(routes, &{&1.key, &1.participant_ref}),
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: initial_variables,
      plan: plan,
      plan_digest: plan_digest(plan),
      state: :prepared,
      room_id: plan.room_id,
      created_at: now(options),
      started_at: nil,
      ended_at: nil
    }
  end

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

  defp registries(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])

    case Keyword.get(options, :registries, Keyword.get(configured, :registries)) do
      value when is_map(value) -> {:ok, value}
      _unavailable -> {:error, :registries_unavailable}
    end
  end

  defp plan_digest(plan) do
    plan
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
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
