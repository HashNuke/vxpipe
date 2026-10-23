defmodule Vxpipe.Console.OAuth.ConsentPage do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="dark" />
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href="/assets/admin-ui.css" />
        <title>Connect client · Vxpipe</title>
      </head>
      <body class="vx-admin access-ui">
        <main class="access-auth oauth-consent">
          <p class="access-auth-mark">Vxpipe · MCP connection</p>
          <h1>Connect {@consent.client_name}</h1>
          <p class="access-lead">This client is asking to act on your behalf through the Vxpipe API. Only continue if you started this connection and trust the client.</p>
          <dl class="oauth-destinations">
            <dt>API</dt><dd>{@consent.resource}</dd>
            <dt>Return to</dt><dd>{@consent.redirect_uri}</dd>
          </dl>
          <h2>Access you are approving</h2>
          <p class="access-muted">The client can use the permissions below while your account retains them. Changes to your role or access require a new connection.</p>
          <ul class="oauth-permissions">
            <li :for={grant <- Map.get(@consent.authority, "grants", [])}>{grant}</li>
          </ul>
          <p :if={Map.get(@consent.authority, "grants", []) == []} class="access-muted">No action permissions are available for this account.</p>
          <div :if={Map.get(@consent.authority, "all_tenant_actions", []) != []}>
            <h2>Across all tenants, including future tenants</h2>
            <ul class="oauth-permissions"><li :for={action <- @consent.authority["all_tenant_actions"]}>{action}</li></ul>
          </div>
          <div :if={Map.get(@consent.authority, "assigned_tenants", %{}) != %{}}>
            <h2>Assigned tenants</h2>
            <ul class="oauth-permissions"><li :for={{tenant, access} <- Enum.sort(@consent.authority["assigned_tenants"])}>{tenant} — {access_label(access)}</li></ul>
          </div>
          <p class="access-muted">You can revoke this connection from Your account at any time. Access ends after 30 days unless you connect again.</p>
          <form action={"/oauth/authorize/" <> @id} method="post" class="access-form">
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <button class="oauth-approve" type="submit" name="decision" value="approve">Allow connection</button>
            <button class="oauth-deny" type="submit" name="decision" value="deny">Deny</button>
          </form>
        </main>
      </body>
    </html>
    """
  end

  defp access_label("read_write"), do: "read and write"
  defp access_label(_access), do: "read"
end
