defmodule Vxpipe.Persistence.MCP.OAuthAttemptStore do
  @moduledoc "Encrypted, expiring and single-claim outbound OAuth attempts; no network work inside transactions."
  @behaviour Vxpipe.Calls.MCPOAuthAttemptRepository
  import Ecto.Query
  alias Vxpipe.Persistence.{ProviderCredentialScope, Schema.MCPOAuthAttempt}
  alias Vxpipe.Persistence.MCP.{RepositoryBoundary, SecretCipher}
  alias Vxpipe.Calls.ResolvedMCPOAuthAttempt
  @private [log: false, telemetry_event: nil]
  @binding_keys [
    :operation,
    :return_to,
    :connection_id,
    :generation,
    :user_id,
    :session_id,
    :issuer,
    :redirect_uri,
    :resource,
    :draft_revision,
    :installation_revision
  ]
  @authority_keys ~w(user_id session_id installation_revision redirect_uri)

  def issue(context, tenant, attributes, secrets)
      when is_binary(tenant) and is_map(attributes) and is_map(secrets) do
    now = now(context)
    attributes = Map.put_new(attributes, :operation, "create")

    with :ok <- validate(attributes, now) do
      transaction(context, fn repo ->
        owner = unwrap!(repo, ProviderCredentialScope.owner(repo, tenant, "FOR UPDATE"))

        count =
          repo.aggregate(
            from(a in MCPOAuthAttempt,
              where: a.tenant_id == ^owner.id and is_nil(a.claimed_at) and a.expires_at > ^now
            ),
            :count,
            :id,
            @private
          )

        if count >= 8, do: repo.rollback(:oauth_attempt_busy)
        id = Ecto.UUID.generate()

        binding =
          attributes
          |> Map.take(@binding_keys)
          |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

        {key_id, encrypted} =
          case encrypt(context, tenant, id, binding, attributes, secrets) do
            {:ok, key_id, encrypted} -> {key_id, encrypted}
            {:error, reason} -> repo.rollback(reason)
          end

        record =
          %MCPOAuthAttempt{}
          |> MCPOAuthAttempt.changeset(%{
            public_id: id,
            tenant_id: owner.id,
            state_digest: digest(attributes.state),
            binding: binding,
            expires_at: attributes.expires_at,
            encrypted_payload: encrypted,
            encryption_key_id: key_id
          })
          |> repo.insert(@private)
          |> then(&unwrap!(repo, &1))

        %{id: record.public_id, expires_at: record.expires_at}
      end)
    end
  end

  def issue(_context, _tenant, _attributes, _secrets), do: {:error, :invalid_oauth_attempt}

  def locate(context, state, %{user_id: user, session_id: session})
      when is_binary(state) and byte_size(state) in 32..256 and is_binary(user) and
             is_binary(session) do
    repo = Keyword.fetch!(context, :repo)
    hash = digest(state)
    now = now(context)

    record =
      RepositoryBoundary.call(
        fn ->
          repo.one(
            from(a in MCPOAuthAttempt,
              join: t in assoc(a, :tenant),
              where: a.state_digest == ^hash and is_nil(a.claimed_at) and a.expires_at > ^now,
              select: {t.key, a.binding}
            ),
            @private
          )
        end,
        :mcp_oauth_storage_unavailable
      )

    case record do
      {tenant, %{"user_id" => ^user, "session_id" => ^session}} -> {:ok, tenant}
      {:error, :mcp_oauth_storage_unavailable} = error -> error
      _ -> {:error, :oauth_attempt_unavailable}
    end
  end

  def locate(_context, _state, _authority), do: {:error, :oauth_attempt_unavailable}

  def claim(context, tenant, state, authority)
      when is_binary(tenant) and is_binary(state) and byte_size(state) in 32..256 and
             is_map(authority) do
    transaction(context, fn repo ->
      hash = digest(state)

      record =
        repo.one(
          from(a in MCPOAuthAttempt,
            join: t in assoc(a, :tenant),
            where: t.key == ^tenant and a.state_digest == ^hash,
            lock: fragment("FOR UPDATE OF ?", a)
          ),
          @private
        )

      now = now(context)

      if is_nil(record) or not is_nil(record.claimed_at) or
           DateTime.compare(record.expires_at, now) != :gt,
         do: repo.rollback(:oauth_attempt_unavailable)

      expected = Map.new(authority, fn {key, value} -> {to_string(key), value} end)

      if not Enum.all?(
           @authority_keys,
           &(Map.has_key?(expected, &1) and expected[&1] == record.binding[&1])
         ),
         do: repo.rollback(:oauth_attempt_unavailable)

      payload =
        SecretCipher.decrypt(
          Keyword.get(context, :keyring),
          identity(tenant, record.public_id),
          record.encryption_key_id,
          record.encrypted_payload
        )
        |> then(&unwrap!(repo, &1))

      if payload["binding"] != record.binding or
           payload["state_digest"] != Base.encode64(record.state_digest) or
           payload["expires_at"] != DateTime.to_unix(record.expires_at, :microsecond),
         do: repo.rollback(:oauth_attempt_unavailable)

      record
      |> MCPOAuthAttempt.changeset(%{
        claimed_at: now,
        encrypted_payload: nil,
        encryption_key_id: nil
      })
      |> repo.update(@private)
      |> then(&unwrap!(repo, &1))

      attempt =
        Map.new(@binding_keys, fn key -> {key, record.binding[Atom.to_string(key)]} end)
        |> Map.put(:id, record.public_id)

      %ResolvedMCPOAuthAttempt{attempt: attempt, secrets: payload["secrets"]}
    end)
  end

  def claim(_context, _tenant, _state, _authority), do: {:error, :oauth_attempt_unavailable}

  @doc "Deletes one bounded batch of terminal attempts without decrypting payloads."
  def prune(context, size) when is_integer(size) and size in 1..500 do
    transaction(context, fn repo ->
      now = now(context)

      terminal =
        from(a in MCPOAuthAttempt,
          where: a.expires_at <= ^now or not is_nil(a.claimed_at)
        )

      ids =
        repo.all(
          from(a in terminal,
            order_by: a.id,
            limit: ^size,
            select: a.id,
            lock: "FOR UPDATE SKIP LOCKED"
          ),
          @private
        )

      {processed, _} = repo.delete_all(from(a in MCPOAuthAttempt, where: a.id in ^ids), @private)
      remaining = repo.aggregate(terminal, :count, :id, @private)

      pending =
        repo.all(
          from(a in MCPOAuthAttempt,
            where: a.expires_at > ^now and is_nil(a.claimed_at),
            group_by: a.encryption_key_id,
            select: {a.encryption_key_id, count(a.id)}
          ),
          @private
        )

      %{processed: processed, remaining: remaining, pending_by_key: Map.new(pending)}
    end)
  end

  def prune(_context, _size), do: {:error, :invalid_oauth_prune_batch_size}

  defp validate(attributes, now) do
    with %{
           state: state,
           expires_at: %DateTime{} = expires,
           connection_id: connection,
           generation: generation,
           installation_revision: revision
         } <- attributes,
         true <- attributes.operation in ["create", "replace"],
         true <- valid_return_context?(Map.get(attributes, :return_to)),
         true <- is_binary(state) and byte_size(state) in 32..256,
         {:ok, _} <- Ecto.UUID.cast(connection),
         true <-
           is_integer(generation) and generation > 0 and is_integer(revision) and revision >= 0,
         true <- DateTime.diff(expires, now, :microsecond) in 1..600_000_000,
         true <-
           Enum.all?(
             [:user_id, :session_id, :issuer, :redirect_uri, :resource, :draft_revision],
             fn key ->
               value = Map.get(attributes, key)
               is_binary(value) and byte_size(value) in 1..2048 and String.valid?(value)
             end
           ) do
      :ok
    else
      _invalid -> {:error, :invalid_oauth_attempt}
    end
  end

  defp valid_return_context?(nil), do: true

  defp valid_return_context?(path),
    do: is_binary(path) and byte_size(path) in 1..16_384 and String.valid?(path)

  defp encrypt(context, tenant, id, binding, attributes, secrets),
    do:
      SecretCipher.encrypt(Keyword.get(context, :keyring), identity(tenant, id), %{
        "binding" => binding,
        "state_digest" => Base.encode64(digest(attributes.state)),
        "expires_at" => DateTime.to_unix(attributes.expires_at, :microsecond),
        "secrets" => secrets
      })

  defp identity(tenant, id),
    do: %{
      tenant_key: tenant,
      connection_id: id,
      generation: 1,
      auth_method: "oauth",
      purpose: "attempt"
    }

  defp digest(state), do: :crypto.hash(:sha256, state)
  defp now(context), do: Keyword.get(context, :now, &DateTime.utc_now/0).()
  defp unwrap!(_repo, {:ok, value}), do: value
  defp unwrap!(repo, {:error, %Ecto.Changeset{}}), do: repo.rollback(:invalid_oauth_attempt)
  defp unwrap!(repo, {:error, reason}), do: repo.rollback(reason)

  defp transaction(context, operation) do
    RepositoryBoundary.call(
      fn ->
        repo = Keyword.fetch!(context, :repo)
        repo.transaction(fn -> operation.(repo) end, @private)
      end,
      :mcp_oauth_storage_unavailable
    )
  end
end
