defmodule Vxpipe.Identity.OAuth do
  @moduledoc "OAuth domain boundary over configured credential and browser persistence ports."

  alias Vxpipe.Identity.OAuth.Delegation

  @errors [
    :invalid_request,
    :invalid_client,
    :invalid_client_metadata,
    :invalid_redirect_uri,
    :invalid_grant,
    :invalid_token,
    :invalid_session,
    :invalid_scope,
    :invalid_target,
    :unsupported_grant_type,
    :unauthorized_client,
    :access_denied,
    :forbidden,
    :not_found,
    :quota_exceeded,
    :rate_limited,
    :unavailable
  ]

  def register_client(metadata), do: credentials(:register_client, [metadata])
  def consent_snapshot(principal), do: credentials(:consent_snapshot, [principal])

  def issue_code(principal, params, resource, expected_snapshot),
    do: credentials(:issue_code, [principal, params, resource, expected_snapshot])

  def exchange(params, resource), do: credentials(:exchange, [params, resource])
  def revoke(params, resource), do: credentials(:revoke, [params, resource])

  def rate_limit(operation, client_address),
    do: credentials(:rate_limit, [operation, client_address])

  @doc "Constructs delegated authority only after the store verifies the token and resource binding."
  def authenticate(token, resource) do
    case credentials(:authenticate, [token, resource]) do
      {:ok, %{user: user, role: role, grant: grant}}
      when is_map(user) and is_map(role) and is_map(grant) ->
        case Delegation.principal(user, role, grant) do
          {:ok, principal} -> {:ok, principal}
          {:error, :invalid_grant} -> {:error, :invalid_token}
        end

      {:error, _reason} = error ->
        error

      _invalid ->
        {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def begin_authorization(params, resource, browser_binding),
    do: browser(:begin_authorization, [params, resource, browser_binding])

  def consent(transaction_id, browser_binding, principal),
    do: browser(:consent, [transaction_id, browser_binding, principal])

  def complete_authorization(transaction_id, browser_binding, principal, decision),
    do: browser(:complete_authorization, [transaction_id, browser_binding, principal, decision])

  def list_grants(principal), do: browser(:list_grants, [principal])
  def revoke_grant(principal, grant_id), do: browser(:revoke_grant, [principal, grant_id])

  defp credentials(operation, arguments), do: invoke(:oauth_store, operation, arguments)
  defp browser(operation, arguments), do: invoke(:oauth_browser_store, operation, arguments)

  defp invoke(configuration, operation, arguments) do
    with module when is_atom(module) and not is_nil(module) <-
           Application.get_env(:vxpipe_identity, configuration) do
      case apply(module, operation, arguments) do
        :ok -> :ok
        {:ok, value} -> {:ok, value}
        {:error, reason} when reason in @errors -> {:error, reason}
        _invalid -> {:error, :unavailable}
      end
    else
      _unconfigured -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end
end
