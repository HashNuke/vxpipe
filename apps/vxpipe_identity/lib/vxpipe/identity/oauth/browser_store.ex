defmodule Vxpipe.Identity.OAuth.BrowserStore do
  @moduledoc """
  Browser authorization port configured as `:vxpipe_identity, :oauth_browser_store`.

  The adapter validates the current browser session and binds each expiring
  authorization transaction to its browser binding. Consent completion checks the
  rendered authority snapshot atomically. Grant lists and revocation are scoped to
  the authenticated user, and lists contain safe metadata rather than credentials.
  """

  alias Vxpipe.Identity.Principal

  @callback begin_authorization(map(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, atom()}
  @callback consent(String.t(), String.t(), Principal.t()) :: {:ok, map()} | {:error, atom()}
  @callback complete_authorization(String.t(), String.t(), Principal.t(), :approve | :deny) ::
              {:ok, map()} | {:error, atom()}
  @callback list_grants(Principal.t()) :: {:ok, [map()]} | {:error, atom()}
  @callback revoke_grant(Principal.t(), String.t()) :: :ok | {:error, atom()}
end
