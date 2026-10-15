defmodule Vxpipe.Identity.Ports.Users do
  @moduledoc """
  Atomic user persistence port implemented by `vxpipe_persistence`.

  Account writes carry trusted actor attribution stamped by `Accounts`: either
  `actor_user_public_id` and its session, or `actor_api_key_public_id` for the
  narrow platform-key account API. Stores must revalidate authority in the same
  transaction as the write and audit event. Machine authority requires an active
  exact-platform installation key locked through commit; it does not authorize
  password resets or arbitrary role management.

  Partial updates retain omitted account fields. Audit attribution resolves the
  public actor identifier to its foreign key inside the transaction; failed audit
  insertion must roll back the account mutation.
  """

  @callback fetch_by_email(normalized_email :: String.t()) ::
              {:ok, map()} | {:error, :not_found | :unavailable}
  @callback fetch_by_public_id(public_id :: String.t()) ::
              {:ok, map()} | {:error, :not_found | :unavailable}
  @callback create(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback apply_update(public_id :: String.t(), changes :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback list(filters :: map()) ::
              {:ok, %{users: [map()], total: non_neg_integer()}} | {:error, term()}
  @callback count_enabled_superadmins() :: {:ok, non_neg_integer()} | {:error, term()}
end
