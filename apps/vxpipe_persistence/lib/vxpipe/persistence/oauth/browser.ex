defmodule Vxpipe.Persistence.OAuth.Browser do
  @moduledoc "Browser-bound one-time consent and self-service connected clients."
  @behaviour Vxpipe.Identity.OAuth.BrowserStore
  import Ecto.Query
  alias Vxpipe.Identity.{ApiKeyActor, OAuth.Profile}

  alias Vxpipe.Persistence.OAuth.{
    Authority,
    AuthorizationRequest,
    Client,
    Clients,
    Grant,
    Store,
    Transaction
  }

  alias Vxpipe.Persistence.Repo

  @impl true
  def begin_authorization(params, resource, binding) do
    with true <- opaque?(binding),
         {:ok, params} <- Profile.authorization(params, resource),
         {:ok, _client} <- Clients.resolve(params["client_id"]) do
      Transaction.run(fn -> create_request(params, resource, binding) end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  @impl true
  def consent(id, binding, principal) do
    Transaction.run(fn ->
      with {:ok, context} <- Authority.browser(principal),
           {:ok, request} <- request(id, binding),
           {:ok, request} <- bind(request, principal.session_public_id, context.snapshot),
           %Client{} = client <- request_client(request) do
        {:ok, presentation(client, request, context.user.email)}
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_request}
      end
    end)
  end

  @impl true
  def complete_authorization(id, binding, principal, decision)
      when decision in [:approve, :deny] do
    Transaction.run(fn ->
      with {:ok, context} <- Authority.browser(principal),
           {:ok, request} <- request(id, binding),
           true <- request.session_public_id == principal.session_public_id,
           true <- request.snapshot == json_snapshot(context.snapshot),
           %Client{} = client <- request_client(request),
           {:ok, response} <- complete(request, principal, context.snapshot, decision) do
        Repo.delete!(request, Transaction.options())

        receipt = %{
          state: if(decision == :approve, do: "allowed", else: "denied"),
          consent: presentation(client, request, context.user.email),
          expires_at: Map.get(response, :expires_at)
        }

        {:ok, Map.put(response, :receipt, receipt)}
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_request}
      end
    end)
  end

  def complete_authorization(_, _, _, _), do: {:error, :invalid_request}

  @impl true
  def list_grants(principal) do
    Transaction.run(fn ->
      with {:ok, context} <- Authority.browser(principal) do
        now = Transaction.now()

        grants =
          Repo.all(
            from(g in Grant,
              join: c in Client,
              on: c.public_id == g.client_id,
              where:
                g.user_id == ^context.user_id and is_nil(g.revoked_at) and g.expires_at > ^now,
              order_by: [desc: g.inserted_at, asc: g.public_id],
              limit: 100,
              select: {g, c}
            ),
            Transaction.options()
          )

        {:ok,
         Enum.map(grants, fn {grant, client} ->
           %{
             public_id: grant.public_id,
             client_name: client.metadata["client_name"],
             resource: grant.resource,
             inserted_at: grant.inserted_at,
             expires_at: grant.expires_at
           }
         end)}
      end
    end)
  end

  @impl true
  def revoke_grant(principal, grant_id) do
    if ApiKeyActor.valid_id?(grant_id) do
      Transaction.run(fn ->
        with {:ok, context} <- Authority.browser(principal),
             %Grant{} = grant <-
               Repo.one(
                 from(g in Grant,
                   where: g.public_id == ^grant_id and g.user_id == ^context.user_id,
                   lock: "FOR UPDATE"
                 ),
                 Transaction.options()
               ) do
          Authority.revoke(grant)
          :ok
        else
          nil -> {:error, :not_found}
          error -> error
        end
      end)
    else
      {:error, :not_found}
    end
  end

  defp create_request(params, resource, binding) do
    # Serializes the global/per-browser quotas across application nodes.
    Repo.query!("SELECT pg_advisory_xact_lock(764918321)", [], Transaction.options())
    now = Transaction.now()

    expired =
      from(r in AuthorizationRequest, where: r.expires_at <= ^now, limit: 100, select: r.digest)

    Repo.delete_all(
      from(r in AuthorizationRequest, where: r.digest in subquery(expired)),
      Transaction.options()
    )

    digest = Transaction.digest(binding)
    active = from(r in AuthorizationRequest, where: r.expires_at > ^now)
    own = from(r in active, where: r.binding_digest == ^digest)

    with %Client{} = client <- Clients.find(params["client_id"], "FOR SHARE"),
         true <-
           Profile.redirect_matches?(params["redirect_uri"], client.metadata["redirect_uris"]),
         :ok <- quota(active, 10_000),
         :ok <- quota(own, 10) do
      id = Transaction.random()

      Repo.insert!(
        %AuthorizationRequest{
          digest: Transaction.digest(id),
          binding_digest: digest,
          client_id: client.public_id,
          client_metadata_digest: Clients.digest(client),
          params: params,
          resource: resource,
          expires_at: DateTime.add(now, 600)
        },
        Transaction.options()
      )

      {:ok, id}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  defp quota(query, limit) do
    if Repo.aggregate(query, :count, :digest, Transaction.options()) < limit,
      do: :ok,
      else: {:error, :quota_exceeded}
  end

  defp request_client(request) do
    client =
      Repo.one(
        from(c in Client, where: c.public_id == ^request.client_id, lock: "FOR SHARE"),
        Transaction.options()
      )

    if client && request.client_metadata_digest == Clients.digest(client), do: client
  end

  defp request(id, binding) do
    if opaque?(id) and opaque?(binding) do
      digest = Transaction.digest(id)

      case Repo.one(
             from(r in AuthorizationRequest, where: r.digest == ^digest, lock: "FOR UPDATE"),
             Transaction.options()
           ) do
        %AuthorizationRequest{} = request ->
          if request.binding_digest == Transaction.digest(binding) and
               Transaction.future?(request.expires_at),
             do: {:ok, request},
             else: {:error, :invalid_request}

        _ ->
          {:error, :invalid_request}
      end
    else
      {:error, :invalid_request}
    end
  end

  defp bind(%AuthorizationRequest{session_public_id: nil} = request, session, snapshot) do
    request
    |> Ecto.Changeset.change(session_public_id: session, snapshot: json_snapshot(snapshot))
    |> Repo.update(Transaction.options())
  end

  defp bind(request, session, snapshot) do
    if request.session_public_id == session and request.snapshot == json_snapshot(snapshot),
      do: {:ok, request},
      else: {:error, :invalid_request}
  end

  defp complete(request, principal, snapshot, :approve),
    do: Store.issue_code(principal, request.params, request.resource, snapshot)

  defp complete(request, _principal, _snapshot, :deny),
    do:
      {:ok,
       %{
         redirect_uri: request.params["redirect_uri"],
         state: request.params["state"],
         error: "access_denied"
       }}

  defp json_snapshot(snapshot), do: snapshot |> JSON.encode!() |> JSON.decode!()

  defp presentation(client, request, email) do
    %{
      client_name: client.metadata["client_name"],
      client_id: client.metadata_url || client.public_id,
      client_uri: branding_uri(client.metadata["client_uri"]),
      logo_uri: branding_uri(client.metadata["logo_uri"]),
      user_email: email,
      grant_lifetime_seconds: Store.grant_lifetime_seconds(),
      redirect_uri: request.params["redirect_uri"],
      resource: request.resource,
      authority: request.snapshot["authority"]
    }
  end

  defp branding_uri(value), do: if(Profile.branding_uri?(value), do: value)

  defp opaque?(value) when is_binary(value) and byte_size(value) == 43,
    do: Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value)

  defp opaque?(_), do: false
end
