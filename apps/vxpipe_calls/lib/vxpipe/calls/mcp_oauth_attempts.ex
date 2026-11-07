defmodule Vxpipe.Calls.MCPOAuthAttempts do
  @moduledoc """
  Authorized persistence boundary for outbound OAuth attempts.

  Called by the server-owned OAuth workflow, never with unvalidated browser
  attributes. Installation identity must be freshly resolved by that workflow.
  State is consumed before network redemption; no token exchange occurs here.
  """
  alias Vxpipe.Calls.{MCPConnectionTarget, MCPOAuthProposal, ProviderAuth, Repositories, UserAuthorization}
  alias Vxpipe.Identity.Principal

  def start(principal, tenant, input, options \\ []) do
    with :ok <- authorize(principal, tenant),
         :ok <- tenant_exists(tenant, options),
         :ok <- refresh(principal, tenant, options),
         :ok <- MCPOAuthProposal.validate(input),
         {:ok, installation} <- installation(options),
         {:ok, port} <- Repositories.fetch(options, :mcp_oauth_preparation),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, target} <-
           MCPConnectionTarget.resolve(port, repository, tenant, input, {:prepare_target, 5}),
         :ok <- refresh(principal, tenant, options),
         :ok <-
           MCPConnectionTarget.lookup(repository, tenant, target, fn ->
             refresh(principal, tenant, options)
           end),
         {:ok, prepared} <- prepare_target(port, tenant, input, installation.origin, target),
         {:ok, current} <- installation(options),
         :ok <- same_installation(installation, current) do
      handoff(
        principal,
        tenant,
        prepared,
        installation,
        %{connection_id: Vxpipe.Calls.PublicId.uuid(), generation: 1, operation: "create"},
        options
      )
    end
  end

  def reconnect(principal, tenant, id, input, options \\ []) do
    with :ok <- authorize(principal, tenant),
         :ok <- tenant_exists(tenant, options),
         :ok <- refresh(principal, tenant, options),
         {:ok, generation} <- reconnect_generation(input),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, connection} <- Repositories.call(repository, :get_retained, [tenant, id]),
         {:ok, input} <- MCPOAuthProposal.saved_input(Map.delete(input, "generation"), connection),
         :ok <- matching_target(connection, tenant, id, generation, input["endpoint"]),
         {:ok, installation} <- installation(options),
         {:ok, port} <- Repositories.fetch(options, :mcp_oauth_preparation),
         {:ok, registration} <- registration(repository, tenant, connection, input),
         {:ok, prepared} <-
           prepare_saved(port, tenant, input, installation.origin, registration, connection),
         {:ok, current} <- installation(options),
         :ok <- same_installation(installation, current),
         target = %{connection_id: id, generation: generation, operation: "replace"},
         {:ok, _} <-
           current_target(tenant, Map.put(target, :resource, input["endpoint"]), options) do
      handoff(principal, tenant, prepared, installation, target, options)
    end
  end

  defp registration(
         repository,
         tenant,
         %{status: "connected", auth_method: "oauth"} = connection,
         input
       ) do
    if Map.has_key?(input, "initial_access_token") or
         (input["auth_method"] != "dcr" and is_nil(Map.get(connection, :directory_entry))) do
      {:ok, %{}}
    else
      Vxpipe.Calls.MCPSavedOAuthRegistration.fetch(repository, tenant, connection)
    end
  end

  defp registration(_repository, _tenant, _connection, _input), do: {:ok, %{}}

  defp prepare_saved(port, tenant, input, origin, registration, connection) do
    arguments = [tenant, input, origin, registration]

    {operation, arguments} =
      case Map.get(connection, :directory_entry) do
        %{} = entry -> {:prepare_saved, arguments ++ [entry]}
        _ -> {:prepare_reconnect, arguments}
      end

    with {:ok, prepared} <- port |> Repositories.call(operation, arguments) |> prepared_result() do
      if MCPOAuthProposal.saved_prepared?(prepared, input, connection),
        do: {:ok, prepared},
        else: {:error, :oauth_preparation_failed}
    end
  end

  defp handoff(principal, tenant, prepared, installation, target, options) do
    attributes =
      prepared.attributes
      |> Map.merge(target)
      |> Map.merge(%{
        installation_revision: installation.revision,
        return_to: Keyword.get(options, :oauth_return_to),
        expires_at: DateTime.add(DateTime.utc_now(), 300)
      })

    with {:ok, attempt} <- issue(principal, tenant, attributes, prepared.secrets, options) do
      {:ok,
       %{
         authorization_url: prepared.authorization_url,
         attempt_id: attempt.id,
         connection_id: target.connection_id
       }}
    end
  end

  defp reconnect_generation(%{"generation" => generation})
       when is_integer(generation) and generation > 0,
       do: {:ok, generation}

  defp reconnect_generation(_), do: {:error, :invalid_oauth_reconnect}

  defp matching_target(connection, tenant, id, generation, endpoint) do
    cond do
      connection.id != id or connection.tenant_key != tenant ->
        {:error, :invalid_oauth_reconnect}

      connection.generation != generation ->
        {:error, :stale_mcp_connection}

      connection.status not in ["connected", "revoked"] ->
        {:error, :invalid_oauth_reconnect}

      connection.endpoint != endpoint ->
        {:error, :invalid_oauth_reconnect}

      true ->
        :ok
    end
  end

  defp current_target(tenant, %{operation: "replace"} = attempt, options) do
    with {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, connection} <-
           Repositories.call(repository, :get_retained, [tenant, attempt.connection_id]),
         :ok <-
           matching_target(
             connection,
             tenant,
             attempt.connection_id,
             attempt.generation,
             attempt.resource
           ),
         do: {:ok, connection}
  end

  defp current_target(_tenant, attempt, _options) do
    if Map.get(attempt, :operation) in [nil, "create"],
      do: {:ok, nil},
      else: {:error, :invalid_oauth_attempt}
  end

  def complete(principal, state, callback, options \\ []) do
    with {:ok, tenant, claimed} <- claim_callback(principal, state, options) do
      complete_claimed(principal, tenant, callback, claimed, options)
    end
  end

  defp complete_claimed(principal, tenant, callback, claimed, options) do
    outcome =
      with {:ok, target} <- current_target(tenant, claimed.attempt, options),
           {:ok, port} <- Repositories.fetch(options, :mcp_oauth_completion),
           {:ok, resolved} <- complete_protocol(port, tenant, callback, claimed),
           do: {:ok, target, resolved}

    with {:ok, current} <- installation(options),
         :ok <- current_installation(claimed.attempt, current),
         :ok <- refresh(principal, tenant, options) do
      result =
        with {:ok, target, resolved} <- outcome,
             {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
             do: save_connection(repository, tenant, claimed.attempt, resolved, target)

      completion_result(result, tenant, claimed.attempt)
    end
  end

  defp completion_result({:ok, record}, tenant, attempt) do
    {:ok, tenant,
     record
     |> Map.take([:id, :tenant_key, :generation, :server_name, :auth_method, :status])
     |> Map.put(:return_to, Map.get(attempt, :return_to))
     |> Map.put(:attempt_id, Map.get(attempt, :id))}
  end

  defp completion_result({:error, reason}, tenant, attempt) do
    {:error, reason,
     %{
       tenant_key: tenant,
       return_to: Map.get(attempt, :return_to),
       attempt_id: Map.get(attempt, :id)
     }}
  end

  defp save_connection(repository, tenant, attempt, resolved, nil) do
    Repositories.call(repository, :create_oauth, [
      tenant,
      attempt.connection_id,
      resolved.connection,
      resolved.secrets
    ])
  end

  defp save_connection(repository, tenant, attempt, resolved, target) do
    attributes = Map.put(resolved.connection, :directory_id, target.directory_id)

    Repositories.call(repository, :replace, [
      tenant,
      attempt.connection_id,
      attempt.generation,
      attributes,
      resolved.secrets
    ])
  end

  defp complete_protocol(port, tenant, callback, claimed) do
    case Repositories.call(port, :complete, [tenant, callback, claimed]) do
      {:ok, %Vxpipe.Calls.ResolvedMCPConnection{connection: connection} = resolved} ->
        if connection.id == claimed.attempt.connection_id and
             connection.generation == claimed.attempt.generation and
             connection.auth_method == "oauth" and
             MCPOAuthProposal.completed?(connection, claimed),
           do: {:ok, resolved},
           else: {:error, :oauth_completion_failed}

      {:error, reason}
      when reason in [
             :oauth_issuer_mismatch,
             :oauth_consent_denied,
             :oauth_authorization_failed,
             :oauth_grant_rejected,
             :oauth_token_exchange_failed,
             :invalid_oauth_token_response,
             :mcp_connection_failed
           ] ->
        {:error, reason}

      _ ->
        {:error, :oauth_completion_failed}
    end
  end

  defp current_installation(attempt, current) do
    if attempt.installation_revision == current.revision and
         attempt.redirect_uri == Map.get(current, :redirect_uri),
       do: :ok,
       else: {:error, :mcp_installation_changed}
  end

  defp prepare_target(port, tenant, input, origin, target) do
    with {:ok, prepared} <-
           port |> Repositories.call(:prepare_target, [tenant, input, origin, target]) |> prepared_result() do
      if MCPOAuthProposal.prepared?(prepared, input) and MCPConnectionTarget.prepared?(prepared, target),
        do: {:ok, prepared},
        else: {:error, :oauth_preparation_failed}
    end
  end

  defp prepared_result(result) do
    case result do
      {:ok, %Vxpipe.Calls.PreparedMCPOAuth{} = prepared} ->
        {:ok, prepared}

      {:error, reason}
      when reason in [
             :invalid_oauth_preparation,
             :invalid_own_oauth_configuration,
             :oauth_browser_grant_required,
             :invalid_mcp_endpoint,
             :invalid_mcp_listing,
             :mcp_listing_unavailable,
             :invalid_oauth_issuer,
             :oauth_issuer_required,
             :unsupported_oauth_capabilities,
             :oauth_registration_unavailable,
             :oauth_registration_failed,
             :mcp_connection_busy
           ] ->
        {:error, reason}

      _ ->
        {:error, :oauth_preparation_failed}
    end
  end

  defp installation(options) do
    case Keyword.get(options, :installation_identity) do
      callback when is_function(callback, 0) ->
        case callback.() do
          {:ok, %{origin: origin, revision: revision} = identity}
          when is_binary(origin) and is_integer(revision) and revision >= 0 ->
            {:ok, identity}

          _ ->
            {:error, :mcp_installation_unavailable}
        end

      _ ->
        {:error, :mcp_installation_unavailable}
    end
  end

  defp same_installation(identity, identity), do: :ok
  defp same_installation(_, _), do: {:error, :mcp_installation_changed}

  def issue(principal, tenant, attributes, secrets, options \\ []) do
    with :ok <- authorize(principal, tenant),
         :ok <- tenant_exists(tenant, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_oauth_attempt_repository),
         :ok <- refresh(principal, tenant, options) do
      bound = Map.merge(attributes, identity(principal))
      Repositories.call(repository, :issue, [tenant, bound, secrets])
    end
  end

  def claim_callback(principal, state, options \\ [])

  def claim_callback(%Principal{credential_kind: :browser_session} = principal, state, options) do
    with {:ok, repository} <- Repositories.fetch(options, :mcp_oauth_attempt_repository),
         {:ok, tenant} <- Repositories.call(repository, :locate, [state, identity(principal)]),
         :ok <- authorize(principal, tenant),
         {:ok, installation} <- installation(options),
         redirect when is_binary(redirect) <- Map.get(installation, :redirect_uri),
         {:ok, claimed} <-
           claim(
             principal,
             tenant,
             state,
             %{installation_revision: installation.revision, redirect_uri: redirect},
             options
           ) do
      {:ok, tenant, claimed}
    else
      {:error, _} = error -> error
      _ -> {:error, :mcp_installation_unavailable}
    end
  end

  def claim_callback(_principal, _state, _options), do: {:error, :forbidden}

  def claim(principal, tenant, state, installation, options \\ []) do
    with :ok <- authorize(principal, tenant),
         :ok <- tenant_exists(tenant, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_oauth_attempt_repository),
         :ok <- refresh(principal, tenant, options) do
      authority =
        installation
        |> Map.take([:installation_revision, :redirect_uri])
        |> Map.merge(identity(principal))

      Repositories.call(repository, :claim, [tenant, state, authority])
    end
  end

  defp identity(principal),
    do: %{user_id: principal.user_public_id, session_id: principal.session_public_id}

  defp authorize(%Principal{credential_kind: :browser_session} = principal, tenant) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         do: UserAuthorization.authorize_tenant_service_write(principal, tenant)
  end

  defp authorize(_principal, _tenant), do: {:error, :forbidden}

  defp tenant_exists(tenant, options) do
    with {:ok, repository} <- Repositories.fetch(options, :credential_repository),
         {:ok, %Vxpipe.Calls.Tenant{key: ^tenant}} <-
           Repositories.call(repository, :fetch_tenant, [tenant]) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp refresh(original, tenant, options) do
    case Keyword.get(options, :refresh_authority) do
      refresh when is_function(refresh, 0) ->
        case refresh.() do
          {:ok, %Principal{} = current} ->
            if identity(current) == identity(original),
              do: authorize(current, tenant),
              else: {:error, :forbidden}

          _ ->
            {:error, :mcp_authority_unavailable}
        end

      _ ->
        {:error, :mcp_authority_unavailable}
    end
  end
end
