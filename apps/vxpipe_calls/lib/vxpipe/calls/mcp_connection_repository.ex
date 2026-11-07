defmodule Vxpipe.Calls.MCPConnectionRepository do
  @moduledoc """
  Trusted tenant-only MCP persistence port.

  Calls authorizes the principal and validates endpoint/authentication/catalog
  before writes. The repository serializes identity and generation changes;
  network work must happen before entering its transactions. Configuration
  generation changes on replacement or revocation, but never on key rotation.
  """

  @callback create(term(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_oauth(term(), String.t(), String.t(), map(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback list(term(), String.t()) :: {:ok, [map()]} | {:error, atom()}
  @callback get(term(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  @doc "Metadata without decryption, including revoked identity; callers enforce authority and status."
  @callback get_retained(term(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  @doc "Finds the deterministic tenant endpoint-or-directory match, including revoked metadata, without decryption."
  @callback find_identity(term(), String.t(), map()) :: {:ok, map() | nil} | {:error, atom()}
  @callback resolve(term(), String.t(), String.t()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPConnection.t()} | {:error, atom()}
  @callback replace(term(), String.t(), String.t(), pos_integer(), map(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback revoke(term(), String.t(), String.t(), pos_integer()) ::
              {:ok, map()} | {:error, atom()}
  @callback refresh_catalog(term(), String.t(), String.t(), pos_integer(), map()) ::
              {:ok, map()} | {:error, atom()}
end
