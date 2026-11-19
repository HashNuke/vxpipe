defmodule Vxpipe.Identity.DiagnosticsSettings do
  @moduledoc "Browser-session administration of the installation's passive benchmark opt-in."
  alias Vxpipe.Identity.Principal

  def fetch(deps, actor) do
    with :ok <- authorize(actor), do: dispatch(deps, :fetch, [actor])
  end

  def update(deps, actor, enabled, revision) do
    with :ok <- authorize(actor),
         :ok <- validate_change(enabled, revision) do
      dispatch(deps, :update, [actor, enabled, revision])
    end
  end

  @doc false
  def validate_change(enabled, revision) do
    with :ok <- validate_enabled(enabled), do: validate_revision(revision)
  end

  def authorize(%Principal{
        account_kind: kind,
        credential_kind: :browser_session,
        user_public_id: user,
        session_public_id: session,
        oauth_grant_public_id: nil,
        delegation: nil
      })
      when kind in [:admin, :superadmin] and is_binary(user) and byte_size(user) > 0 and
             is_binary(session) and byte_size(session) > 0,
      do: :ok

  def authorize(_actor), do: {:error, :forbidden}

  defp validate_enabled(enabled) when is_boolean(enabled), do: :ok
  defp validate_enabled(_enabled), do: {:error, :invalid_enabled}

  # Leave room for the next revision in the database's signed bigint.
  defp validate_revision(revision)
       when is_integer(revision) and revision in 0..9_223_372_036_854_775_806,
       do: :ok

  defp validate_revision(_revision), do: {:error, :invalid_revision}

  defp dispatch(%{diagnostics_settings: port}, operation, args) when is_atom(port) do
    if Code.ensure_loaded?(port) and function_exported?(port, operation, length(args)),
      do: apply(port, operation, args),
      else: {:error, :unavailable}
  end

  defp dispatch(_deps, _operation, _args), do: {:error, :unavailable}
end
