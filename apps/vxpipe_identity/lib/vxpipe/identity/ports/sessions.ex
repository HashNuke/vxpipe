defmodule Vxpipe.Identity.Ports.Sessions do
  @moduledoc "Atomic session persistence port. Only digests cross this boundary."

  @callback create(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback fetch_valid(digest :: String.t(), now :: DateTime.t()) :: {:ok, map()} | {:error, :not_found | :expired | :revoked | :disabled | :unavailable}
  @callback revoke_one(digest :: String.t(), now :: DateTime.t()) :: :ok | {:error, term()}
  @callback revoke_for_user(user_public_id :: String.t(), now :: DateTime.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback revoke_for_role(role_public_id :: String.t(), now :: DateTime.t()) :: {:ok, non_neg_integer()} | {:error, term()}
end
