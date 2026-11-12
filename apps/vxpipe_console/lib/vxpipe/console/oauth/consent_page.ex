defmodule Vxpipe.Console.OAuth.ConsentPage do
  @moduledoc false
  use Phoenix.Component
  alias Vxpipe.Console.Endpoint

  def unavailable, do: render(%{consent: nil, id: nil, csrf_token: nil})

  def receipt(receipt, id, callback) do
    render(%{
      consent: receipt.consent,
      id: id,
      csrf_token: nil,
      state: receipt.state,
      completion: %{callback: callback, expires_at: receipt.expires_at}
    })
  end

  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:state, if(assigns.consent, do: "consent", else: "unavailable"))
      |> Map.put_new(:completion, nil)

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="dark" />
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href={Endpoint.static_path("/assets/admin-ui.css")} />
        <link rel="stylesheet" href={Endpoint.static_path("/assets/oauth.css")} />
        <title>{if @consent, do: "Connect client", else: "Connection unavailable"} · Vxpipe</title>
      </head>
      <body>
        <div id="oauth-root" data-state={@state} data-consent={if @consent, do: Jason.encode!(@consent)} data-request-id={@id} data-csrf-token={@csrf_token} data-completion={if @completion, do: Jason.encode!(@completion)}></div>
        <script type="module" src={Endpoint.static_path("/assets/oauth.js")}></script>
        <noscript>
        <div :if={@state == "consent"} class="vx-admin access-ui">
        <main class="access-auth oauth-consent">
          <p class="access-auth-mark">Vxpipe · MCP connection</p>
          <h1>Connect {@consent.client_name}</h1>
          <p>Signed in as {@consent.user_email}</p>
          <p class="access-lead">This client is asking to act on your behalf through the Vxpipe API. Only continue if you started this connection and trust the client.</p>
          <dl class="oauth-destinations">
            <dt>Client ID</dt>
            <dd>{@consent.client_id}</dd>
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
          <p class="access-muted">You can revoke this connection from Settings → Your connections at any time. Access ends after {div(@consent.grant_lifetime_seconds, 86_400)} days unless you connect again.</p>
          <form action={"/oauth/authorize/" <> @id} method="post" class="access-form">
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <button class="oauth-approve" type="submit" name="decision" value="approve">Allow connection</button>
            <button class="oauth-deny" type="submit" name="decision" value="deny">Deny</button>
          </form>
        </main>
        </div>
        <main :if={is_nil(@consent)} class="vx-admin oauth-preview oauth-preview-main">
          <h1>This request can’t be completed</h1>
          <p>Start a new connection from your client.</p>
          <a href="/">Back to Vxpipe</a>
        </main>
        <main :if={@completion} class="vx-admin oauth-preview oauth-preview-main">
          <h1>{if @state == "allowed", do: "Access approved", else: "Connection declined"}</h1>
          <p>Return to {@consent.client_name} to finish this request.</p>
          <a href={@completion.callback} rel="noreferrer">Back to my app</a>
        </main>
        </noscript>
      </body>
    </html>
    """
  end

  defp access_label("read_write"), do: "read and write"
  defp access_label(_access), do: "read"
end
