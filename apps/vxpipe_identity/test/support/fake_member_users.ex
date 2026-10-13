defmodule Vxpipe.Identity.FakeMemberUsers do
  @moduledoc "Static member user used for stale-edit checks."
  @behaviour Vxpipe.Identity.Ports.Users

  @impl true
  def fetch_by_email(_email), do: {:error, :not_found}

  @impl true
  def fetch_by_public_id("user-1"),
    do:
      {:ok,
       %{
         public_id: "user-1",
         email: "user@example.com",
         normalized_email: "user@example.com",
         password_hash: "hash:x",
         role_public_id: "role-member",
         role_kind: :member,
         memberships: %{}
       }}

  def fetch_by_public_id(_), do: {:error, :not_found}

  @impl true
  def create(attrs), do: {:ok, attrs}

  @impl true
  def apply_update(id, _changes), do: {:error, {:not_found, id}}

  @impl true
  def list(_filters), do: {:ok, %{users: [], total: 0}}

  @impl true
  def count_enabled_superadmins, do: {:ok, 1}
end
