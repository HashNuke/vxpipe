defmodule Vxpipe.Console.Test.FakeUserIdentity do
  @moduledoc """
  Cohesive test fake for the Console user-identity backend.

  Returns a real `Vxpipe.Identity.Principal` with full built-in grants so
  endpoint tests exercise the named `UserSession` (`/auth/api/login`) path
  without a database. Configure per test via `setup`/`on_exit`, never globally.
  """

  alias Vxpipe.Identity.{Permission, Principal}

  @email "owner@example.test"
  @password "long-password"
  @token String.duplicate("x", 43)
  @user_id "test-owner"
  @session_id "test-session"

  @spec email() :: String.t()
  def email, do: @email

  @spec password() :: String.t()
  def password, do: @password

  @spec token() :: String.t()
  def token, do: @token

  @spec principal() :: Principal.t()
  def principal do
    grants = Permission.catalog() |> Enum.map(& &1.key) |> MapSet.new()

    {:ok, principal} =
      Principal.new(%{
        user_public_id: @user_id,
        session_public_id: @session_id,
        account_kind: :superadmin,
        grants: grants,
        assigned_tenants: %{},
        all_tenant_actions: grants
      })

    principal
  end

  @spec status() :: {:ok, :complete}
  def status, do: {:ok, :complete}

  def setup(email, password, confirmation, proof, address, _public_url),
    do: setup(email, password, confirmation, proof, address)

  @spec setup(String.t(), String.t(), String.t(), term(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def setup(@email, @password, @password, _proof, _address),
    do: {:ok, %{token: @token, user: %{public_id: @user_id}}}

  def setup(_, _, _, _, _), do: {:error, :invalid_password}

  @spec login(String.t(), String.t(), term()) :: {:ok, map()} | {:error, term()}
  def login(@email, @password, _address),
    do: {:ok, %{token: @token, user: %{public_id: @user_id}}}

  def login(_, _, _), do: {:error, :invalid_credentials}

  @spec logout(term()) :: :ok
  def logout(_token), do: :ok

  @spec authenticate(String.t()) :: {:ok, Principal.t()} | {:error, term()}
  def authenticate(@token), do: {:ok, principal()}
  def authenticate(_token), do: {:error, :invalid_session}

  @spec issue_setup_proof() :: {:error, :unavailable}
  def issue_setup_proof, do: {:error, :unavailable}

  @spec session_details(map()) :: {:ok, {map(), map()}}
  def session_details(_principal) do
    {:ok,
     {%{
        public_id: @user_id,
        email: @email,
        role_public_id: "role-superadmin",
        disabled_at: nil,
        memberships: %{}
      },
      %{
        public_id: "role-superadmin",
        name: "Superadmin",
        description: "",
        kind: :superadmin,
        revision: 1,
        grants: []
      }}}
  end

  @spec list_users(map(), map()) :: {:error, :forbidden}
  def list_users(_actor, _filters), do: {:error, :forbidden}

  @spec get_user(map(), String.t()) :: {:error, :forbidden}
  def get_user(_actor, _id), do: {:error, :forbidden}

  @spec create_user(map(), map()) :: {:error, :forbidden}
  def create_user(_actor, _attrs), do: {:error, :forbidden}

  @spec update_user(map(), String.t(), map()) :: {:error, :forbidden}
  def update_user(_actor, _id, _attrs), do: {:error, :forbidden}

  @spec reset_password(map(), String.t(), String.t(), String.t()) :: {:error, :forbidden}
  def reset_password(_actor, _id, _password, _confirmation), do: {:error, :forbidden}

  @spec update_account(map(), String.t(), String.t() | nil, String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def update_account(%{user_public_id: @user_id}, @password, email, _password, _confirmation)
      when is_binary(email) do
    {:ok,
     %{
       public_id: @user_id,
       email: email,
       role_public_id: "role-superadmin",
       disabled_at: nil,
       memberships: %{}
     }}
  end

  def update_account(_actor, _current_password, _email, _password, _confirmation),
    do: {:error, :invalid_credentials}

  @spec list_roles(map(), map()) :: {:error, :forbidden}
  def list_roles(_actor, _filters), do: {:error, :forbidden}

  @spec get_role(map(), String.t()) :: {:error, :forbidden}
  def get_role(_actor, _id), do: {:error, :forbidden}

  @spec list_role_options(map()) :: {:error, :forbidden}
  def list_role_options(_actor), do: {:error, :forbidden}

  @spec create_role(map(), map()) :: {:error, :forbidden}
  def create_role(_actor, _attrs), do: {:error, :forbidden}

  @spec update_role(map(), String.t(), map()) :: {:error, :forbidden}
  def update_role(_actor, _id, _attrs), do: {:error, :forbidden}

  @spec delete_role(map(), String.t()) :: {:error, :forbidden}
  def delete_role(_actor, _id), do: {:error, :forbidden}
end
