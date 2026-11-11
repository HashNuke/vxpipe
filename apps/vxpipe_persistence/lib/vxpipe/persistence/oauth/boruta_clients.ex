defmodule Vxpipe.Persistence.OAuth.BorutaClients do
  @moduledoc false
  @behaviour Boruta.Oauth.Clients
  alias Vxpipe.Identity.OAuth.Profile
  alias Vxpipe.Persistence.OAuth.{BorutaContext, Client, Transaction}
  alias Vxpipe.Persistence.Repo

  @impl true
  def get_client(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Client{} = client <- Repo.get(Client, id, Transaction.options()) do
      %Boruta.Oauth.Client{
        id: client.public_id,
        name: client.metadata["client_name"],
        confidential: false,
        pkce: true,
        public_refresh_token: true,
        public_revoke: true,
        authorize_scope: false,
        redirect_uris: redirect_uris(client),
        supported_grant_types: client.metadata["grant_types"],
        token_endpoint_auth_methods: ["none"],
        access_token_ttl: 600,
        authorization_code_ttl: 60,
        refresh_token_ttl: 2_592_000
      }
    else
      _ -> nil
    end
  end

  @impl true
  def authorized_scopes(_client), do: [%Boruta.Oauth.Scope{name: "mcp"}]

  defp redirect_uris(client) do
    registered = client.metadata["redirect_uris"]

    case BorutaContext.current() do
      %{grant: %{client_id: id}, redirect_uri: redirect} when id == client.public_id ->
        if Profile.redirect_matches?(redirect, registered), do: [redirect], else: registered

      _ ->
        registered
    end
  end
end
