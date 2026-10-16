defmodule Vxpipe.Persistence.OAuth.Store do
  @moduledoc "Durable OAuth credentials over real Boruta, with Vxpipe resource and authority checks."
  @behaviour Vxpipe.Identity.OAuth.Store
  import Ecto.Query
  alias Vxpipe.Identity.OAuth.Profile

  alias Vxpipe.Persistence.OAuth.{
    Authority,
    BorutaContext,
    BorutaResourceOwners,
    BorutaResponse,
    Client,
    Credentials,
    Grant,
    RateLimit,
    Retention,
    Token,
    Transaction
  }

  alias Vxpipe.Persistence.Repo

  @impl true
  def register_client(metadata) do
    with {:ok, metadata} <- Profile.registration(metadata) do
      Transaction.run(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(764918320)", [], Transaction.options())
        Retention.sweep(100)

        if Repo.aggregate(Client, :count, :public_id, Transaction.options()) < 10_000 do
          client = Repo.insert!(%Client{metadata: metadata}, Transaction.options())
          {:ok, Map.put(metadata, :client_id, client.public_id)}
        else
          {:error, :quota_exceeded}
        end
      end)
    end
  end

  @impl true
  def consent_snapshot(principal) do
    Transaction.run(fn ->
      with {:ok, context} <- Authority.browser(principal), do: {:ok, context.snapshot}
    end)
  end

  @impl true
  def issue_code(principal, params, resource, expected_snapshot) do
    with {:ok, params} <- Profile.authorization(params, resource) do
      Transaction.run(fn -> code_for(principal, params, resource, expected_snapshot) end)
    end
  end

  @impl true
  def exchange(params, resource) do
    with {:ok, params} <- Profile.token(params, resource) do
      Transaction.run(fn -> exchange_for(params, resource) end)
    end
  end

  @impl true
  def authenticate(raw, resource) when is_binary(raw) and byte_size(raw) in 1..256,
    do: Transaction.run(fn -> Credentials.access(raw, resource) end)

  def authenticate(_, _), do: {:error, :invalid_token}

  @impl true
  def revoke(params, resource) do
    with {:ok, params} <- Profile.revocation(params),
         do: Transaction.run(fn -> Credentials.revoke(params, resource) end)
  end

  defdelegate cleanup(limit), to: Retention
  @impl true
  defdelegate rate_limit(operation, address), to: RateLimit, as: :check

  defp code_for(principal, params, resource, expected_snapshot) do
    with {:ok, context} <- Authority.browser(principal),
         true <- context.snapshot == expected_snapshot,
         %Client{} = client <-
           Repo.one(
             from(c in Client, where: c.public_id == ^params["client_id"], lock: "FOR KEY SHARE"),
             Transaction.options()
           ),
         true <- params["redirect_uri"] in client.metadata["redirect_uris"],
         :ok <- Retention.expire_user_grants(context.user_id),
         :ok <- grant_quota(context.user_id),
         grant <- create_grant(context, params, resource) do
      context |> Map.put(:grant, grant) |> authorize_with_boruta(params)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  defp authorize_with_boruta(context, params) do
    BorutaContext.run(context, fn ->
      conn = %Plug.Conn{method: "GET", query_params: params, body_params: %{}, params: params}
      owner = BorutaResourceOwners.owner(context.user.public_id, context.grant.public_id)

      with {:ok, response} <- Boruta.Oauth.authorize(conn, owner, BorutaResponse) do
        {:ok,
         %{
           code: response.code,
           state: response.state,
           redirect_uri: params["redirect_uri"],
           grant_id: context.grant.public_id
         }}
      end
    end)
  end

  defp exchange_for(params, resource) do
    with {:ok, context} <- Credentials.prepare(params, resource),
         :ok <- token_quota(context.grant.public_id) do
      BorutaContext.run(context, fn ->
        params =
          if params["grant_type"] == "refresh_token",
            do: Map.put_new(params, "scope", "mcp"),
            else: params

        conn = %Plug.Conn{method: "POST", body_params: params, query_params: %{}, params: params}
        Boruta.Oauth.token(conn, BorutaResponse)
      end)
    end
  end

  defp create_grant(context, params, resource) do
    attrs =
      context.snapshot
      |> Map.take([:authorization_version, :role_public_id, :role_revision, :authority])
      |> Map.merge(%{
        user_id: context.user_id,
        client_id: params["client_id"],
        resource: resource,
        expires_at: DateTime.add(Transaction.now(), 2_592_000)
      })

    Repo.insert!(struct!(Grant, attrs), Transaction.options())
  end

  defp grant_quota(user_id) do
    now = Transaction.now()

    count =
      Repo.aggregate(
        from(g in Grant,
          where: g.user_id == ^user_id and g.expires_at > ^now and is_nil(g.revoked_at)
        ),
        :count,
        :public_id,
        Transaction.options()
      )

    if count < 100, do: :ok, else: {:error, :quota_exceeded}
  end

  defp token_quota(grant_id) do
    count =
      Repo.aggregate(
        from(t in Token, where: t.grant_id == ^grant_id),
        :count,
        :public_id,
        Transaction.options()
      )

    if count < 10_000, do: :ok, else: {:error, :quota_exceeded}
  end
end
