defmodule Vxpipe.Calls.MCPConnections do
  @moduledoc "User-authorized tenant MCP management. No platform inheritance or anonymous failure fallback."
  alias Vxpipe.Calls.{
    MCPDiscoveryProposal,
    MCPRuntimeCredentials,
    ProviderAuth,
    Repositories,
    ResolvedMCPConnection,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal

  @public_fields [
    :id,
    :tenant_key,
    :endpoint,
    :directory_id,
    :directory_entry,
    :server_name,
    :auth_method,
    :generation,
    :status,
    :namespace,
    :oauth
  ]
  @probe_errors [
    :invalid_mcp_configuration,
    :invalid_mcp_endpoint,
    :invalid_mcp_authentication,
    :invalid_mcp_listing,
    :mcp_listing_unavailable,
    :mcp_connection_timed_out,
    :mcp_connection_busy,
    :mcp_authentication_required,
    :invalid_own_oauth_configuration,
    :invalid_oauth_issuer,
    :oauth_issuer_required,
    :oauth_machine_grant_required
  ]

  def preflight(principal, tenant, input, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- MCPDiscoveryProposal.validate(input),
         :ok <- refresh(principal, tenant, options),
         {:ok, probe} <- Repositories.fetch(options, :mcp_preflight),
         {:ok, result} <- discover(probe, tenant, input, options),
         :ok <- refresh(principal, tenant, options) do
      {:ok, result}
    end
  end

  defp discover(probe, tenant, %{"connection_id" => _} = input, options),
    do: Vxpipe.Calls.MCPSavedPreflight.discover(probe, tenant, input, options)

  defp discover(probe, tenant, input, _options) do
    case Repositories.call(probe, :discover, [tenant, input]) do
      {:ok, result} ->
        if MCPDiscoveryProposal.matches?(result, input),
          do: {:ok, result},
          else: {:error, :mcp_discovery_unavailable}

      {:error, reason}
      when reason in [
             :invalid_mcp_endpoint,
             :invalid_mcp_preflight,
             :invalid_mcp_listing,
             :mcp_listing_unavailable,
             :invalid_oauth_issuer,
             :mcp_connection_busy,
             :mcp_connection_timed_out
           ] ->
        {:error, reason}

      _failed ->
        {:error, :mcp_discovery_unavailable}
    end
  end

  def get(principal, tenant, id, options \\ []) do
    with :ok <- authorize(principal, tenant, :read),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, 1),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, %{id: ^id, tenant_key: ^tenant} = record} <-
           Repositories.call(repository, :get, [tenant, id]) do
      {:ok,
       record
       |> public()
       |> Map.put(:tools, Map.get(record, :catalog, []))
       |> Map.put(:can_edit, authorize(principal, tenant, :write) == :ok)}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :mcp_connection_not_found}
    end
  end

  @doc "Public reconnect configuration for an explicitly selected revoked generation, without decryption."
  def get_retained(principal, tenant, id, generation, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, generation),
         :ok <- refresh(principal, tenant, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, record} <- Repositories.call(repository, :get_retained, [tenant, id]),
         :ok <- current(record, tenant, id, generation),
         :ok <- revoked(record),
         :ok <- refresh(principal, tenant, options) do
      {:ok, Map.put(public(record), :can_edit, true)}
    end
  end

  def list(principal, tenant, options \\ []) do
    with :ok <- authorize(principal, tenant, :read),
         :ok <- tenant_exists(tenant, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, records} <- Repositories.call(repository, :list, [tenant]) do
      if Enum.all?(records, &(&1.tenant_key == tenant)),
        do: {:ok, Enum.map(records, &public/1)},
        else: {:error, :mcp_connections_unavailable}
    end
  end

  def connect(principal, tenant, input, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- input(input),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, checked} <- check(options, tenant, input),
         :ok <- refresh(principal, tenant, options),
         {:ok, record} <- create(repository, tenant, checked) do
      project(record, tenant)
    end
  end

  defp create(repository, tenant, checked) do
    case Repositories.call(repository, :create, [tenant, checked.connection, checked.secrets]) do
      {:error, {:mcp_connection_exists, id}} -> existing_identity(repository, tenant, id)
      result -> result
    end
  end

  defp existing_identity(repository, tenant, id) do
    case Repositories.call(repository, :get_retained, [tenant, id]) do
      {:ok, %{tenant_key: ^tenant, id: ^id, status: "revoked", generation: generation}}
      when is_integer(generation) and generation > 0 ->
        {:error, {:mcp_reconnect_required, %{id: id, generation: generation}}}

      {:ok, %{tenant_key: ^tenant, id: ^id, status: "connected"}} ->
        {:error, {:mcp_connection_exists, id}}

      {:error, _} = error ->
        error

      _ ->
        {:error, :mcp_connections_unavailable}
    end
  end

  def update(principal, tenant, id, generation, input, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, generation),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, saved} <- Repositories.call(repository, :get_retained, [tenant, id]),
         :ok <- current(saved, tenant, id, generation),
         :ok <- connected(saved),
         {:ok, input} <- saved_input(input, saved),
         {:ok, input} <- edit_input(input, saved, repository, tenant, id),
         :ok <- input(input),
         {:ok, checked} <- check_saved(options, tenant, input, saved),
         :ok <- refresh(principal, tenant, options),
         {:ok, record} <-
           Repositories.call(repository, :replace, [
             tenant,
             id,
             generation,
             checked.connection,
             checked.secrets
           ]) do
      if record.id == id,
        do: project(record, tenant),
        else: {:error, :mcp_connections_unavailable}
    end
  end

  def reconnect(principal, tenant, id, generation, input, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, generation),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, saved} <- Repositories.call(repository, :get_retained, [tenant, id]),
         :ok <- current(saved, tenant, id, generation),
         :ok <- revoked(saved),
         {:ok, input} <- saved_input(input, saved),
         :ok <- input(input),
         {:ok, checked} <- check_saved(options, tenant, input, saved),
         :ok <- same_endpoint(saved, checked.connection),
         :ok <- refresh(principal, tenant, options),
         {:ok, record} <-
           Repositories.call(repository, :replace, [
             tenant,
             id,
             generation,
             checked.connection,
             checked.secrets
           ]) do
      if record.id == id,
        do: project(record, tenant),
        else: {:error, :mcp_connections_unavailable}
    end
  end

  defp connected(%{status: "connected"}), do: :ok
  defp connected(_), do: {:error, :mcp_connection_revoked}
  defp revoked(%{status: "revoked"}), do: :ok
  defp revoked(_), do: {:error, :mcp_reconnect_not_required}

  defp same_endpoint(saved, checked) do
    if saved.endpoint == checked.endpoint and saved.directory_id == checked.directory_id,
      do: :ok,
      else: {:error, :invalid_mcp_configuration}
  end

  def disconnect(principal, tenant, id, generation, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, generation),
         :ok <- refresh(principal, tenant, options),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, record} <- Repositories.call(repository, :revoke, [tenant, id, generation]) do
      if record.id == id,
        do: project(record, tenant),
        else: {:error, :mcp_connections_unavailable}
    end
  end

  def refresh_tools(principal, tenant, id, generation, options \\ []) do
    with :ok <- authorize(principal, tenant, :write),
         :ok <- tenant_exists(tenant, options),
         :ok <- identity(id, generation),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, saved} <- Repositories.call(repository, :resolve, [tenant, id]),
         :ok <- current(saved, tenant, id, generation),
         {:ok, input} <- refresh_input(saved, tenant, id, generation, options),
         {:ok, checked} <- check(options, tenant, input),
         :ok <- refresh(principal, tenant, options),
         {:ok, record} <-
           Repositories.call(repository, :refresh_catalog, [
             tenant,
             id,
             generation,
             Map.take(checked.connection, [:server_name, :catalog])
           ]) do
      if record.id == id,
        do: project(record, tenant),
        else: {:error, :mcp_connections_unavailable}
    end
  end

  defp refresh_input(
         %ResolvedMCPConnection{connection: %{auth_method: "oauth"}} = saved,
         tenant,
         id,
         generation,
         options
       ) do
    with {:ok, current} <- MCPRuntimeCredentials.resolve(tenant, id, generation, options) do
      {:ok,
       %{
         "endpoint" => saved.connection.endpoint,
         "auth_method" => "bearer",
         "credentials" => %{
           "token" => current.secrets["access_token"],
           "headers" => Map.get(saved.secrets, "headers", [])
         }
       }}
    end
  end

  defp refresh_input(saved, _, _, _, _) do
    {:ok,
     %{
       "endpoint" => saved.connection.endpoint,
       "auth_method" => saved.connection.auth_method,
       "credentials" => saved.secrets
     }}
  end

  defp current(%ResolvedMCPConnection{connection: connection}, tenant, id, generation),
    do: current(connection, tenant, id, generation)

  defp current(%{tenant_key: _, id: _, generation: _} = connection, tenant, id, generation) do
    cond do
      connection.tenant_key != tenant or connection.id != id ->
        {:error, :not_found}

      connection.generation != generation ->
        {:error, :stale_mcp_connection}

      true ->
        :ok
    end
  end

  defp current(_saved, _tenant, _id, _generation), do: {:error, :not_found}

  defp saved_input(_input, %{directory_entry: %{}, auth_method: "oauth"}),
    do: {:error, :oauth_reconnect_required}

  defp saved_input(input, %{directory_entry: %{}} = saved) when is_map(input) do
    if Map.keys(input) -- ~w(endpoint auth_method credentials) == [],
      do:
        {:ok,
         Map.merge(input, %{"endpoint" => saved.endpoint, "auth_method" => saved.auth_method})},
      else: {:error, :invalid_mcp_configuration}
  end

  defp saved_input(input, _saved), do: {:ok, input}

  defp edit_input(input, saved, repository, tenant, id)
       when is_map(input) do
    cond do
      Map.has_key?(input, "credentials") ->
        {:ok, input}

      input["endpoint"] == saved.endpoint and input["auth_method"] == saved.auth_method ->
        with {:ok, resolved} <- Repositories.call(repository, :resolve, [tenant, id]),
             :ok <- current(resolved, tenant, id, saved.generation),
             do: {:ok, Map.put(input, "credentials", resolved.secrets)}

      true ->
        {:error, :invalid_mcp_configuration}
    end
  end

  defp edit_input(_input, _saved, _repository, _tenant, _id),
    do: {:error, :invalid_mcp_configuration}

  defp tenant_exists(tenant, options) do
    with {:ok, repository} <- Repositories.fetch(options, :credential_repository),
         {:ok, %Vxpipe.Calls.Tenant{key: ^tenant}} <-
           Repositories.call(repository, :fetch_tenant, [tenant]) do
      :ok
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :not_found}
    end
  end

  defp authorize(%Principal{credential_kind: :browser_session} = principal, tenant, access) do
    with :ok <- ProviderAuth.tenant_key(tenant) do
      case access do
        :read -> UserAuthorization.authorize_tenant_service_read(principal, tenant)
        :write -> UserAuthorization.authorize_tenant_service_write(principal, tenant)
      end
    end
  end

  defp authorize(_principal, _tenant, _access), do: {:error, :forbidden}

  defp refresh(original, tenant, options) do
    case Keyword.get(options, :refresh_authority) do
      refresh when is_function(refresh, 0) ->
        case refresh.() do
          {:ok, %Principal{} = current} ->
            if current.user_public_id == original.user_public_id and
                 current.session_public_id == original.session_public_id,
               do: authorize(current, tenant, :write),
               else: {:error, :forbidden}

          _unavailable ->
            {:error, :mcp_authority_unavailable}
        end

      _missing ->
        {:error, :mcp_authority_unavailable}
    end
  end

  defp input(%{"listing" => reference, "credentials" => credentials} = input)
       when is_map(reference) and is_map(credentials) do
    if Map.keys(input) -- ~w(listing endpoint auth_method credentials) == [] and
         byte_size(JSON.encode!(reference)) <= 8192 and
         byte_size(JSON.encode!(credentials)) <= 65_536,
       do: :ok,
       else: {:error, :invalid_mcp_configuration}
  rescue
    _ -> {:error, :invalid_mcp_configuration}
  end

  defp input(
         %{
           "endpoint" => endpoint,
           "auth_method" => "own_client",
           "revision" => revision,
           "credentials" => %{"grant_type" => "client_credentials"} = credentials
         } = input
       )
       when is_binary(endpoint) and byte_size(endpoint) in 1..2048 and
              is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- ~w(endpoint auth_method credentials revision issuer) == [] and
         byte_size(JSON.encode!(credentials)) <= 65_536,
       do: :ok,
       else: {:error, :invalid_mcp_configuration}
  rescue
    _ -> {:error, :invalid_mcp_configuration}
  end

  defp input(
         %{"endpoint" => endpoint, "auth_method" => method, "credentials" => credentials} = input
       )
       when is_binary(endpoint) and byte_size(endpoint) in 1..2048 and
              method in ~w(none bearer headers basic) and is_map(credentials) do
    if Map.keys(input) -- ~w(endpoint auth_method credentials) == [] and
         byte_size(JSON.encode!(credentials)) <= 65_536,
       do: :ok,
       else: {:error, :invalid_mcp_configuration}
  rescue
    _invalid -> {:error, :invalid_mcp_configuration}
  end

  defp input(_input), do: {:error, :invalid_mcp_configuration}

  defp identity(id, generation)
       when is_binary(id) and byte_size(id) in 1..128 and is_integer(generation) and
              generation > 0,
       do: :ok

  defp identity(_id, _generation), do: {:error, :invalid_mcp_connection}

  defp check(options, tenant, %{"listing" => reference} = input) do
    with {:ok, checked} <- probe(options, :check, [tenant, input]) do
      if matches_listing?(checked.connection, reference),
        do: {:ok, checked},
        else: {:error, :mcp_connection_failed}
    end
  end

  defp check(options, tenant, input) do
    probe(options, :check, [tenant, input])
  end

  defp matches_listing?(
         %{
           directory_entry: %{
             "directory_id" => directory,
             "integration_id" => integration,
             "revision" => revision,
             "endpoint" => endpoint
           },
           endpoint: endpoint,
           directory_id: identity
         },
         %{
           "directory_id" => directory,
           "integration_id" => integration,
           "entry_revision" => revision
         }
       )
       when is_binary(directory) and is_binary(integration),
       do: identity == directory <> "/" <> integration

  defp matches_listing?(_connection, _reference), do: false

  defp check_saved(options, tenant, input, %{directory_entry: %{} = entry} = saved) do
    with {:ok, checked} <- probe(options, :check_saved, [tenant, input, entry]) do
      if Map.get(checked.connection, :directory_entry) == entry and
           Map.get(checked.connection, :endpoint) == saved.endpoint and
           Map.get(checked.connection, :directory_id) == saved.directory_id and
           Map.get(checked.connection, :auth_method) == saved.auth_method,
         do: {:ok, checked},
         else: {:error, :mcp_connection_failed}
    end
  end

  defp check_saved(options, tenant, input, _saved), do: check(options, tenant, input)

  defp probe(options, operation, arguments) do
    with {:ok, probe} <- Repositories.fetch(options, :mcp_connection_probe) do
      case Repositories.call(probe, operation, arguments) do
        {:ok, %ResolvedMCPConnection{connection: configuration, secrets: secrets} = result}
        when is_map(configuration) and is_map(secrets) ->
          {:ok, result}

        {:error, reason} when reason in @probe_errors ->
          {:error, reason}

        _failure ->
          {:error, :mcp_connection_failed}
      end
    end
  end

  defp project(%{tenant_key: tenant} = record, tenant), do: {:ok, public(record)}
  defp project(_record, _tenant), do: {:error, :mcp_connections_unavailable}

  defp public(record),
    do:
      record
      |> Map.take(@public_fields)
      |> Map.put(:tool_count, length(Map.get(record, :catalog, [])))
end
