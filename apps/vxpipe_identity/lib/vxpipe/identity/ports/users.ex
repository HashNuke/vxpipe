defmodule Vxpipe.Identity.Ports.Users do
  @moduledoc "Atomic user persistence port implemented by `vxpipe_persistence`."

  @callback fetch_by_email(normalized_email :: String.t()) :: {:ok, map()} | {:error, :not_found | :unavailable}
  @callback fetch_by_public_id(public_id :: String.t()) :: {:ok, map()} | {:error, :not_found | :unavailable}
  @callback create(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback apply_update(public_id :: String.t(), changes :: map()) :: {:ok, map()} | {:error, term()}
  @callback list(filters :: map()) :: {:ok, %{users: [map()], total: non_neg_integer()}} | {:error, term()}
  @callback count_enabled_superadmins() :: {:ok, non_neg_integer()} | {:error, term()}
end
