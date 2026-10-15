defmodule Vxpipe.Gateway.Test.AccountStore do
  @moduledoc false

  @user "11111111-1111-4111-8111-111111111111"
  @role "22222222-2222-4222-8222-222222222222"
  @key "33333333-3333-4333-8333-333333333333"
  @platform "vxpk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  def user_id, do: @user
  def role_id, do: @role
  def key_id, do: @key
  def platform_secret, do: @platform

  def dependencies,
    do: %{users: __MODULE__, roles: __MODULE__, hasher: __MODULE__, uuid: __MODULE__}

  def generate, do: @user
  def hash(_password), do: {:ok, "private-password-hash"}

  def user do
    %{
      public_id: @user,
      email: "member@example.test",
      role_public_id: @role,
      role_kind: :member,
      disabled_at: nil,
      memberships: %{"AAAAAAAAAAAAAAAA" => :read},
      password_hash: "private-password-hash"
    }
  end

  def fetch(@role),
    do: {:ok, %{public_id: @role, kind: :member, grants: [%{scope: :assigned_tenants}]}}

  def fetch(_id), do: {:error, :not_found}
  def fetch_by_public_id(@user), do: {:ok, user()}
  def fetch_by_public_id(_id), do: {:error, :not_found}

  def list(filters) do
    send(self(), {:account_query, filters})
    failure_or(fn -> {:ok, %{users: [user()], total: 1}} end)
  end

  def list_options(filters) do
    send(self(), {:role_query, filters})

    {:ok,
     %{roles: [%{public_id: @role, name: "Member", kind: :member, grants: [:private]}], total: 1}}
  end

  def create(attrs) do
    send(self(), {:account_create, attrs})

    if Map.has_key?(attrs.memberships, "BBBBBBBBBBBBBBBB"),
      do: {:error, :unknown_tenant},
      else: {:ok, Map.merge(user(), Map.take(attrs, [:email, :role_public_id, :memberships]))}
  end

  def apply_update(_id, attrs) do
    send(self(), {:account_update, attrs})
    disabled_at = if Map.get(attrs, :disabled, false), do: ~U[2026-10-15 00:00:00Z]

    {:ok,
     user()
     |> Map.merge(Map.take(attrs, [:email, :role_public_id, :memberships]))
     |> Map.put(:disabled_at, disabled_at)}
  end

  def authenticate_platform(_context, digest) do
    if digest == :crypto.hash(:sha256, @platform),
      do: {:ok, @key},
      else: {:error, :invalid_api_key}
  end

  def fetch_api_key_by_digest(_context, digest) do
    if digest == :crypto.hash(:sha256, "tenant-key"),
      do:
        {:ok,
         %{
           id: @key,
           tenant_key: "AAAAAAAAAAAAAAAA",
           scopes: MapSet.new([:admin, :calls]),
           revoked_at: nil
         }},
      else: {:error, :not_found}
  end

  defp failure_or(operation) do
    case Process.get({__MODULE__, :failure}) do
      :raise -> raise "private-storage-detail"
      :exit -> exit(:private_storage_detail)
      :error -> {:error, {:private_storage_detail, "private-password-hash"}}
      _ -> operation.()
    end
  end
end
