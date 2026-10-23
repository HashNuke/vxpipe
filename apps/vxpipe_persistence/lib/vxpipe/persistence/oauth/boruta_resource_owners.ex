defmodule Vxpipe.Persistence.OAuth.BorutaResourceOwners do
  @moduledoc false
  @behaviour Boruta.Oauth.ResourceOwners
  @behaviour Boruta.Oauth.Scopes
  alias Vxpipe.Persistence.OAuth.BorutaContext

  @impl true
  def get_by(sub: sub) do
    case BorutaContext.current() do
      %{user: %{public_id: ^sub}, grant: grant} -> {:ok, owner(sub, grant.public_id)}
      _ -> {:error, "Invalid resource owner"}
    end
  end

  def get_by(_), do: {:error, "Invalid resource owner"}

  def owner(sub, grant_id),
    do: %Boruta.Oauth.ResourceOwner{sub: sub, extra_claims: %{"grant_id" => grant_id}}

  @impl true
  def authorized_scopes(_owner), do: [%Boruta.Oauth.Scope{name: "mcp"}]
  @impl true
  def check_password(_owner, _password), do: {:error, "Unsupported grant"}
  @impl true
  def public, do: []
end
