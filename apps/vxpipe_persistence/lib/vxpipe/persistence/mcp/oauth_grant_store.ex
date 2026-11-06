defmodule Vxpipe.Persistence.MCP.OAuthGrantStore do
  @moduledoc "Durable, fenced refresh claims inside the encrypted connection envelope."
  import Ecto.Query
  alias Vxpipe.Persistence.MCP.{RepositoryBoundary, SecretCipher}
  alias Vxpipe.Persistence.Schema.MCPConnection
  @private [log: false, telemetry_event: nil]

  def claim(context, tenant, id, generation, revision) do
    transaction(context, tenant, id, generation, fn repo, record, secrets ->
      current = Map.get(secrets, "grant_revision", 1)
      if current != revision, do: repo.rollback(:stale_oauth_grant)

      if not renewable?(secrets),
        do: repo.rollback(:oauth_reconnect_required)

      case secrets["refresh_claim"] do
        nil ->
          :ok

        claim ->
          if live?(claim, context),
            do: repo.rollback(:oauth_refresh_in_progress),
            else: repo.rollback(:oauth_reconnect_required)
      end

      claim = %{"id" => Ecto.UUID.generate(), "deadline" => now(context) + 30}
      persist!(repo, context, tenant, record, Map.put(secrets, "refresh_claim", claim))
      %Vxpipe.Calls.ResolvedMCPRefresh{id: claim["id"], grant_revision: current, secrets: secrets}
    end)
  end

  def complete(context, tenant, id, generation, claim_id, tokens) do
    result =
      transaction(context, tenant, id, generation, fn repo, record, secrets ->
        claim = secrets["refresh_claim"]
        if not is_map(claim) or claim["id"] != claim_id, do: repo.rollback(:stale_oauth_refresh)
        if not live?(claim, context), do: repo.rollback(:oauth_reconnect_required)
        if not tokens?(tokens, secrets), do: repo.rollback(:invalid_oauth_tokens)

        updated =
          secrets
          |> Map.delete("expires_at")
          |> Map.merge(tokens)
          |> Map.delete("refresh_claim")
          |> Map.put("grant_revision", Map.get(secrets, "grant_revision", 1) + 1)

        persist!(repo, context, tenant, record, updated)
        :ok
      end)

    case result do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  def fail(context, tenant, id, generation, claim_id) do
    result =
      transaction(context, tenant, id, generation, fn repo, record, secrets ->
        claim = secrets["refresh_claim"]
        if not is_map(claim) or claim["id"] != claim_id, do: repo.rollback(:stale_oauth_refresh)

        persist!(
          repo,
          context,
          tenant,
          record,
          Map.put(secrets, "refresh_claim", Map.put(claim, "deadline", 0))
        )

        :ok
      end)

    case result do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  defp transaction(context, tenant, id, generation, operation) do
    RepositoryBoundary.call(
      fn -> transaction_call(context, tenant, id, generation, operation) end,
      :mcp_oauth_storage_unavailable
    )
  end

  defp transaction_call(context, tenant, id, generation, operation) do
    repo = Keyword.fetch!(context, :repo)

    repo.transaction(
      fn ->
        with {:ok, id} <- Ecto.UUID.cast(id) do
          record =
            repo.one(
              from(c in MCPConnection,
                join: t in assoc(c, :tenant),
                where: t.key == ^tenant and c.public_id == ^id,
                lock: fragment("FOR UPDATE OF ?", c)
              ),
              @private
            )

          if is_nil(record) or record.status != "connected" or record.auth_method != "oauth" or
               record.generation != generation,
             do: repo.rollback(:oauth_connection_unavailable)

          secrets =
            unwrap!(
              repo,
              SecretCipher.decrypt(
                Keyword.get(context, :keyring),
                identity(tenant, record),
                record.encryption_key_id,
                record.encrypted_payload
              )
            )

          operation.(repo, record, secrets)
        else
          _ -> repo.rollback(:oauth_connection_unavailable)
        end
      end,
      @private
    )
  end

  defp persist!(repo, context, tenant, record, secrets) do
    {key, encrypted} =
      case SecretCipher.encrypt(Keyword.get(context, :keyring), identity(tenant, record), secrets) do
        {:ok, key, encrypted} -> {key, encrypted}
        {:error, reason} -> repo.rollback(reason)
      end

    record
    |> Ecto.Changeset.change(encryption_key_id: key, encrypted_payload: encrypted)
    |> repo.update(@private)
    |> then(&unwrap!(repo, &1))
  end

  defp identity(tenant, record),
    do: %{
      tenant_key: tenant,
      connection_id: record.public_id,
      generation: record.generation,
      auth_method: "oauth",
      purpose: "connection"
    }

  defp now(context), do: Keyword.get(context, :now, &DateTime.utc_now/0).() |> DateTime.to_unix()

  defp live?(%{"deadline" => deadline}, context) when is_integer(deadline),
    do: deadline > now(context)

  defp live?(_, _), do: false
  defp unwrap!(_repo, {:ok, result}), do: result
  defp unwrap!(repo, {:error, reason}), do: repo.rollback(reason)

  defp renewable?(%{
         "registration_method" => "own_client",
         "grant_type" => "client_credentials",
         "auth_method" => method
       })
       when method in ~w(client_secret_basic client_secret_post private_key_jwt), do: true

  defp renewable?(%{"grant_type" => grant}) when grant != "authorization_code", do: false
  defp renewable?(secrets), do: text?(secrets["refresh_token"])

  defp tokens?(%{"access_token" => token} = tokens, secrets) do
    Map.keys(tokens) -- ~w(access_token refresh_token expires_at scope) == [] and text?(token) and
      (secrets["grant_type"] != "client_credentials" or not Map.has_key?(tokens, "refresh_token")) and
      (not Map.has_key?(tokens, "refresh_token") or text?(tokens["refresh_token"])) and
      (is_nil(tokens["scope"]) or text?(tokens["scope"])) and expiry?(tokens["expires_at"])
  end

  defp tokens?(_, _), do: false
  defp text?(text), do: is_binary(text) and byte_size(text) in 1..32_768 and String.valid?(text)
  defp expiry?(nil), do: true
  defp expiry?(value) when is_binary(value), do: match?({:ok, _, _}, DateTime.from_iso8601(value))
  defp expiry?(_), do: false
end
