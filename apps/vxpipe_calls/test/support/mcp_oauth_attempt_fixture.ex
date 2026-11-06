defmodule Vxpipe.Calls.Test.MCPOAuthAttemptFixture do
  def complete(owner, tenant, _callback, claimed) do
    send(owner, {:attempt_completed, tenant})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: %{
         id: claimed.attempt.connection_id,
         generation: 1,
         auth_method: "oauth",
         server_name: "Calendar"
       },
       secrets: %{"access_token" => "private"}
     }}
  end

  def create_oauth(owner, tenant, id, attributes, secrets) do
    send(owner, {:oauth_saved, tenant, id, secrets})
    {:ok, Map.merge(attributes, %{id: id, tenant_key: tenant})}
  end

  def locate(owner, state, authority) do
    send(owner, {:attempt_locate, state, authority})
    {:ok, "AAAAAAAAAAAAAAAA"}
  end

  def issue(owner, tenant, attributes, secrets) do
    send(owner, {:attempt_issue, tenant, attributes, secrets})
    {:ok, %{id: "attempt"}}
  end

  def claim(owner, tenant, state, authority) do
    send(owner, {:attempt_claim, tenant, state, authority})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPOAuthAttempt{
       attempt: %{
         connection_id: "connection",
         generation: 1,
         installation_revision: 2,
         redirect_uri: "https://console.test/oauth/mcp/callback"
       },
       secrets: %{}
     }}
  end
end
