defmodule Vxpipe.Persistence.MCP.ConnectionStore do
  @moduledoc "Tenant-only MCP records. Callers authorize and validate discovery before writes."
  @behaviour Vxpipe.Calls.MCPConnectionRepository
  import Ecto.Query
  alias Vxpipe.Persistence.{CredentialKeyring, ProviderCredentialScope}
  alias Vxpipe.Persistence.MCP.{DirectoryEntry, RepositoryBoundary, SecretCipher}
  alias Vxpipe.Persistence.Schema.MCPConnection

  @private [log: false, telemetry_event: nil]
  @configuration [
    :endpoint,
    :endpoint_identity,
    :directory_id,
    :directory_entry,
    :server_name,
    :auth_method
  ]

  @impl true
  def create(context, tenant, attributes, secrets) when is_binary(tenant) do
    transaction(context, fn repo ->
      owner = owner!(repo, tenant)
      reject_duplicate!(repo, owner.id, attributes, nil)
      record = %MCPConnection{public_id: Ecto.UUID.generate(), tenant_id: owner.id, generation: 1}
      save!(repo, context, record, tenant, Map.put(attributes, :generation, 1), secrets)
    end)
  end

  def create(_context, _tenant, _attributes, _secrets), do: {:error, :invalid_tenant_key}

  @impl true
  def create_oauth(context, tenant, id, %{auth_method: "oauth"} = attributes, secrets)
      when is_binary(tenant) and is_map(secrets) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        transaction(context, fn repo ->
          owner = owner!(repo, tenant)
          reject_duplicate!(repo, owner.id, attributes, nil)
          record = %MCPConnection{public_id: id, tenant_id: owner.id, generation: 1}
          save!(repo, context, record, tenant, Map.put(attributes, :generation, 1), secrets)
        end)

      _ ->
        {:error, :invalid_oauth_connection}
    end
  end

  def create_oauth(_context, _tenant, _id, _attributes, _secrets),
    do: {:error, :invalid_oauth_connection}

  @impl true
  def list(context, tenant) when is_binary(tenant) do
    transaction(context, fn repo ->
      query =
        from(c in MCPConnection,
          join: t in assoc(c, :tenant),
          where: t.key == ^tenant and c.status == "connected",
          order_by: c.id
        )

      repo.all(query, @private) |> Enum.map(&metadata(&1, tenant))
    end)
  end

  def list(_context, _tenant), do: {:error, :invalid_tenant_key}

  @impl true
  def get(context, tenant, id) when is_binary(tenant) do
    transaction(context, fn repo ->
      record = fetch!(repo, tenant, id)
      if record.status == "revoked", do: repo.rollback(:mcp_connection_not_found)
      public = metadata(record, tenant)

      if record.auth_method == "oauth",
        do: Map.put(public, :oauth, oauth_labels(context, record, tenant)),
        else: public
    end)
  end

  def get(_context, _tenant, _id), do: {:error, :invalid_tenant_key}

  @impl true
  def get_retained(context, tenant, id) when is_binary(tenant) do
    transaction(context, fn repo -> repo |> fetch!(tenant, id) |> metadata(tenant) end)
  end

  def get_retained(_context, _tenant, _id), do: {:error, :invalid_tenant_key}

  @impl true
  def find_identity(context, tenant, %{endpoint_identity: endpoint} = identity)
      when is_binary(tenant) and is_binary(endpoint) do
    transaction(context, fn repo ->
      query =
        from(c in MCPConnection,
          join: t in assoc(c, :tenant),
          where: t.key == ^tenant
        )

      case repo.one(identity_query(query, identity), @private) do
        nil -> nil
        record -> metadata(record, tenant)
      end
    end)
  end

  def find_identity(_context, _tenant, _identity), do: {:error, :invalid_tenant_key}

  @impl true
  def resolve(context, tenant, id) when is_binary(tenant) do
    transaction(context, fn repo ->
      record = fetch!(repo, tenant, id)
      if record.status == "revoked", do: repo.rollback(:mcp_connection_revoked)

      secrets =
        unwrap!(
          repo,
          SecretCipher.decrypt(
            Keyword.get(context, :keyring),
            identity(record, tenant),
            record.encryption_key_id,
            record.encrypted_payload
          )
        )

      %Vxpipe.Calls.ResolvedMCPConnection{connection: metadata(record, tenant), secrets: secrets}
    end)
  end

  def resolve(_context, _tenant, _id), do: {:error, :invalid_tenant_key}

  @impl true
  def replace(context, tenant, id, generation, attributes, secrets) when is_binary(tenant) do
    transaction(context, fn repo ->
      owner = owner!(repo, tenant)
      record = current!(repo, tenant, id, generation)
      reject_duplicate!(repo, owner.id, attributes, id)

      save!(
        repo,
        context,
        record,
        tenant,
        Map.put(attributes, :generation, record.generation + 1),
        secrets
      )
    end)
  end

  def replace(_context, _tenant, _id, _generation, _attributes, _secrets),
    do: {:error, :invalid_tenant_key}

  @impl true
  def revoke(context, tenant, id, generation) when is_binary(tenant) do
    transaction(context, fn repo ->
      _owner = owner!(repo, tenant)
      record = current!(repo, tenant, id, generation)

      record
      |> Ecto.Changeset.change(
        status: "revoked",
        generation: record.generation + 1,
        encrypted_payload: nil,
        encryption_key_id: nil,
        catalog: %{"tools" => []}
      )
      |> repo.update(@private)
      |> then(&unwrap!(repo, &1))
      |> metadata(tenant)
    end)
  end

  def revoke(_context, _tenant, _id, _generation), do: {:error, :invalid_tenant_key}

  @impl true
  def refresh_catalog(
        context,
        tenant,
        id,
        generation,
        %{refreshed_at: refreshed_at, refresh_scheduled_at: scheduled_at},
        %{server_name: name, catalog: catalog} = attributes
      ) do
    transaction(context, fn repo ->
      record = current!(repo, tenant, id, generation)
      if record.status != "connected", do: repo.rollback(:mcp_connection_not_found)

      if record.refreshed_at != refreshed_at or record.refresh_scheduled_at != scheduled_at,
        do: repo.rollback(:stale_mcp_catalog)

      if Map.keys(attributes) -- [:server_name, :catalog] != [],
        do: repo.rollback(:invalid_mcp_configuration)

      if not is_list(catalog) or byte_size(JSON.encode!(catalog)) > 1_048_576,
        do: repo.rollback(:invalid_mcp_catalog)

      record
      |> MCPConnection.changeset(%{
        server_name: DirectoryEntry.name(record.directory_entry, name),
        catalog: %{"tools" => catalog},
        refreshed_at: next_freshness(context, record.refreshed_at)
      })
      |> repo.update(@private)
      |> then(&unwrap!(repo, &1))
      |> metadata(tenant)
    end)
  end

  def refresh_catalog(_, _, _, _, _, _), do: {:error, :invalid_mcp_configuration}

  @doc false
  def catalog_time(context) do
    case Keyword.fetch(context, :now) do
      {:ok, clock} ->
        clock.()

      :error ->
        repo = Keyword.fetch!(context, :repo)
        %{rows: [[now]]} = repo.query!("SELECT clock_timestamp()", [], @private)
        now
    end
  end

  defp next_freshness(context, previous) do
    now = catalog_time(context)

    if previous && DateTime.compare(now, previous) != :gt,
      do: DateTime.add(previous, 1, :microsecond),
      else: now
  end

  def reencrypt(context, size) when is_integer(size) and size in 1..500 do
    transaction(context, fn repo ->
      {current, _key} =
        case CredentialKeyring.current(Keyword.get(context, :keyring)) do
          {:ok, id, key} -> {id, key}
          {:error, reason} -> repo.rollback(reason)
        end

      query =
        from(c in MCPConnection,
          join: t in assoc(c, :tenant),
          where: c.status == "connected" and c.encryption_key_id != ^current,
          order_by: c.id,
          limit: ^size,
          select: {c, t.key},
          lock: fragment("FOR UPDATE OF ? SKIP LOCKED", c)
        )

      rows = repo.all(query, @private)

      Enum.each(rows, fn {record, tenant} ->
        binding = identity(record, tenant)
        keyring = Keyword.get(context, :keyring)

        payload =
          unwrap!(
            repo,
            SecretCipher.decrypt(
              keyring,
              binding,
              record.encryption_key_id,
              record.encrypted_payload
            )
          )

        {key_id, encrypted} = encrypt!(repo, keyring, binding, payload)

        unwrap!(
          repo,
          repo.update(
            Ecto.Changeset.change(record,
              encryption_key_id: key_id,
              encrypted_payload: encrypted
            ),
            @private
          )
        )
      end)

      remaining =
        repo.all(
          from(c in MCPConnection,
            where: c.status == "connected" and c.encryption_key_id != ^current,
            group_by: c.encryption_key_id,
            select: {c.encryption_key_id, count(c.id)}
          ),
          @private
        )

      %{processed: length(rows), current_key_id: current, remaining_by_key: Map.new(remaining)}
    end)
  end

  def reencrypt(_context, _size), do: {:error, :invalid_reencryption_batch_size}

  defp save!(repo, context, record, tenant, attributes, secrets) do
    attributes = unwrap!(repo, DirectoryEntry.bind(attributes, record.directory_entry))
    catalog = Map.get(attributes, :catalog, [])

    if not is_list(catalog) or byte_size(JSON.encode!(catalog)) > 1_048_576,
      do: repo.rollback(:invalid_mcp_catalog)

    changes =
      Map.take(attributes, @configuration)
      |> Map.merge(%{
        status: "connected",
        catalog: %{"tools" => catalog},
        refreshed_at: next_freshness(context, record.refreshed_at),
        refresh_scheduled_at: nil,
        generation: Map.get(attributes, :generation, record.generation)
      })

    draft = struct(record, changes)

    {key_id, encrypted} =
      encrypt!(repo, Keyword.get(context, :keyring), identity(draft, tenant), secrets)

    values =
      Map.merge(changes, %{
        generation: draft.generation,
        encryption_key_id: key_id,
        encrypted_payload: encrypted
      })

    changeset = MCPConnection.changeset(record, values)

    stored =
      if Ecto.get_meta(record, :state) == :built,
        do: repo.insert(changeset, @private),
        else: repo.update(changeset, @private)

    metadata(unwrap!(repo, stored), tenant)
  end

  defp encrypt!(repo, keyring, identity, secrets) do
    case SecretCipher.encrypt(keyring, identity, secrets) do
      {:ok, id, encrypted} -> {id, encrypted}
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp owner!(repo, tenant),
    do: unwrap!(repo, ProviderCredentialScope.owner(repo, tenant, "FOR UPDATE"))

  defp fetch!(repo, tenant, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        repo.one(
          from(c in MCPConnection,
            join: t in assoc(c, :tenant),
            where: t.key == ^tenant and c.public_id == ^id,
            lock: fragment("FOR UPDATE OF ?", c)
          ),
          @private
        ) || repo.rollback(:mcp_connection_not_found)

      :error ->
        repo.rollback(:mcp_connection_not_found)
    end
  end

  defp current!(repo, tenant, id, generation) do
    record = fetch!(repo, tenant, id)
    if record.generation != generation, do: repo.rollback(:stale_mcp_connection)
    record
  end

  defp reject_duplicate!(repo, tenant_id, attributes, except) do
    query = from(c in MCPConnection, where: c.tenant_id == ^tenant_id)
    query = if except, do: from(c in query, where: c.public_id != ^except), else: query

    case repo.one(identity_query(query, attributes), @private) do
      nil -> :ok
      record -> repo.rollback({:mcp_connection_exists, record.public_id})
    end
  end

  defp identity_query(query, attributes) do
    endpoint = Map.fetch!(attributes, :endpoint_identity)
    directory = Map.get(attributes, :directory_id)

    query =
      if directory,
        do:
          from(c in query,
            where: c.endpoint_identity == ^endpoint or c.directory_id == ^directory
          ),
        else: from(c in query, where: c.endpoint_identity == ^endpoint)

    from(c in query, order_by: c.id, limit: 1)
  end

  defp identity(record, tenant),
    do: %{
      tenant_key: tenant,
      connection_id: record.public_id,
      generation: record.generation,
      auth_method: record.auth_method,
      purpose: "connection"
    }

  defp metadata(record, tenant) do
    %{
      id: record.public_id,
      tenant_key: tenant,
      endpoint: record.endpoint,
      endpoint_identity: record.endpoint_identity,
      directory_id: record.directory_id,
      directory_entry: record.directory_entry,
      server_name: record.server_name,
      auth_method: record.auth_method,
      generation: record.generation,
      status: record.status,
      catalog: Map.fetch!(record.catalog, "tools"),
      refreshed_at: record.refreshed_at,
      refresh_scheduled_at: record.refresh_scheduled_at,
      namespace: "mcp_" <> String.replace(record.public_id, "-", "")
    }
  end

  defp oauth_labels(context, record, tenant) do
    with {:ok, secrets} <-
           SecretCipher.decrypt(
             Keyword.get(context, :keyring),
             identity(record, tenant),
             record.encryption_key_id,
             record.encrypted_payload
           ),
         registration when registration in ~w(cimd dcr own_client) <-
           secrets["registration_method"],
         grant when grant in ~w(authorization_code client_credentials) <-
           Map.get(secrets, "grant_type", "authorization_code"),
         method when method in ~w(none client_secret_basic client_secret_post private_key_jwt) <-
           secrets["auth_method"] do
      %{"registration_method" => registration, "grant_type" => grant, "auth_method" => method}
    else
      _ -> nil
    end
  end

  defp unwrap!(_repo, {:ok, result}), do: result
  defp unwrap!(repo, {:error, %Ecto.Changeset{}}), do: repo.rollback(:invalid_mcp_connection)
  defp unwrap!(repo, {:error, reason}), do: repo.rollback(reason)

  defp transaction(context, operation) do
    RepositoryBoundary.call(
      fn ->
        repo = Keyword.fetch!(context, :repo)
        repo.transaction(fn -> operation.(repo) end, @private)
      end,
      :mcp_connections_unavailable
    )
  end
end
