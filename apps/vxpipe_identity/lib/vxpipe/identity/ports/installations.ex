defmodule Vxpipe.Identity.Ports.Installations do
  @moduledoc "Typed authentication singleton port, distinct from demo setup."

  @callback fetch() :: {:ok, map()} | {:error, :missing | :corrupt | :unavailable}
  @callback update_public_url(Vxpipe.Identity.Principal.t(), String.t(), non_neg_integer()) ::
              {:ok, map()} | {:error, term()}
  @optional_callbacks update_public_url: 3
  @callback complete_first_run(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback consume_setup_proof(proof :: String.t(), attrs :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback issue_setup_proof(ttl_seconds :: pos_integer()) ::
              {:ok, %{proof: String.t()}} | {:error, term()}
  @callback issue_recovery_proof(ttl_seconds :: pos_integer()) ::
              {:ok, %{proof: String.t()}} | {:error, term()}
  @callback consume_recovery_proof(proof :: String.t(), attrs :: map()) ::
              {:ok, map()} | {:error, term()}
end
