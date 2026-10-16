defmodule Vxpipe.Identity.OAuth.Store do
  @moduledoc """
  Durable OAuth credential port configured as `:vxpipe_identity, :oauth_store`.

  The adapter owns atomic code consumption, refresh rotation and replay revocation.
  Authentication must check credential expiry, revocation and exact resource binding
  before returning freshly loaded user, role and approved grant records. Identity
  then constructs a delegated principal; a browser session or API-key actor is never
  an acceptable authentication result.
  """

  alias Vxpipe.Identity.Principal

  @callback register_client(map()) :: {:ok, map()} | {:error, atom()}
  @callback consent_snapshot(Principal.t()) :: {:ok, map()} | {:error, atom()}
  @callback issue_code(Principal.t(), map(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  @callback exchange(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback revoke(map(), String.t()) :: :ok | {:error, atom()}
  @callback authenticate(String.t(), String.t()) ::
              {:ok, %{user: map(), role: map(), grant: map()}} | {:error, atom()}
  @callback rate_limit(:register | :authorize | :token | :revoke, String.t()) ::
              :ok | {:error, atom()}
end
