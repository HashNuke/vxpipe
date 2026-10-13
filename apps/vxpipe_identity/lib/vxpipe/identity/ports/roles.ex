defmodule Vxpipe.Identity.Ports.Roles do
  @moduledoc "Atomic role persistence port."

  @callback fetch(public_id :: String.t()) :: {:ok, map()} | {:error, :not_found | :unavailable}
  @callback fetch_by_slug(slug :: String.t()) :: {:ok, map()} | {:error, :not_found | :unavailable}
  @callback list() :: {:ok, [map()]} | {:error, term()}
  @callback create(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback apply_update(public_id :: String.t(), changes :: map()) :: {:ok, map()} | {:error, term()}
  @callback delete(public_id :: String.t()) :: :ok | {:error, term()}
  @callback count_users(public_id :: String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
end
