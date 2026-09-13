defmodule Vxpipe.Console.OperatorSignInPage do
  @moduledoc false

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href="/assets/call_inspection.css" />
        <title>Sign in · Vxpipe Calls</title>
      </head>
      <body class="operator-page">
        <main class="sign-in-shell">
          <header class="sign-in-brand">
            <a href="/" aria-label="Open Vxpipe voice console">Vxpipe</a>
            <span>Call inspection</span>
          </header>
          <section class="sign-in-panel" aria-labelledby="sign-in-heading">
            <div class="sign-in-copy">
              <h1 id="sign-in-heading">Sign in to inspect calls</h1>
              <p>
                Use a tenant API key with the calls scope. The key authenticates this request
                and is not stored in the browser session.
              </p>
            </div>
            <div :if={@error} class="form-error" role="alert">{@error}</div>
            <form action="/operator/session" method="post" class="sign-in-form">
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <label>
                <span>Tenant key</span>
                <input
                  type="text"
                  name="operator[tenant_key]"
                  value={@tenant_key}
                  autocomplete="organization"
                  autocapitalize="none"
                  spellcheck="false"
                  required
                />
              </label>
              <label>
                <span>API key</span>
                <input
                  type="password"
                  name="operator[api_key]"
                  autocomplete="current-password"
                  spellcheck="false"
                  required
                />
              </label>
              <button type="submit">Sign in</button>
            </form>
          </section>
          <p class="sign-in-footnote">
            Caller join tokens do not grant operator access.
          </p>
        </main>
      </body>
    </html>
    """
  end
end
