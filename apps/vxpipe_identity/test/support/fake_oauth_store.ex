defmodule Vxpipe.Identity.FakeOAuthStore do
  @moduledoc false
  @behaviour Vxpipe.Identity.OAuth.Store
  @behaviour Vxpipe.Identity.OAuth.BrowserStore

  def register_client(metadata), do: respond(:register_client, [metadata])
  def consent_snapshot(principal), do: respond(:consent_snapshot, [principal])

  def issue_code(principal, params, resource, snapshot),
    do: respond(:issue_code, [principal, params, resource, snapshot])

  def exchange(params, resource), do: respond(:exchange, [params, resource])
  def revoke(params, resource), do: respond(:revoke, [params, resource])
  def authenticate(token, resource), do: respond(:authenticate, [token, resource])
  def rate_limit(operation, address), do: respond(:rate_limit, [operation, address])

  def begin_authorization(params, resource, binding),
    do: respond(:begin_authorization, [params, resource, binding])

  def consent(id, binding, principal), do: respond(:consent, [id, binding, principal])

  def complete_authorization(id, binding, principal, decision),
    do: respond(:complete_authorization, [id, binding, principal, decision])

  def list_grants(principal), do: respond(:list_grants, [principal])
  def revoke_grant(principal, id), do: respond(:revoke_grant, [principal, id])

  defp respond(operation, arguments) do
    send(self(), {:oauth_store, operation, arguments})

    case Process.get({__MODULE__, :response}, :ok) do
      :raise -> raise "private-oauth-sentinel"
      :exit -> exit("private-oauth-sentinel")
      :throw -> throw("private-oauth-sentinel")
      response -> response
    end
  end
end
