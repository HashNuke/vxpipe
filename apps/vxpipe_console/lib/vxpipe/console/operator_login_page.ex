defmodule Vxpipe.Console.OperatorLoginPage do
  @moduledoc false

  use Phoenix.Component

  def guidance(assigns), do: page(assigns, :guidance)
  def code(assigns), do: page(assigns, :code)
  def unavailable(assigns), do: page(assigns, :unavailable)

  defp page(assigns, view) do
    assigns = Map.put(assigns, :view, view)

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="dark" />
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href="/assets/operator_login.css" />
        <title>Operator login · Vxpipe</title>
      </head>
      <body class="operator-login-page">
        <main class="operator-login-shell">
          <header class="operator-login-brand"><span>Vxpipe</span><span>Operator</span></header>
          <section class="operator-login-panel">
            <div :if={@view == :guidance}>
              <p class="operator-login-label">Local access</p>
              <h1>Open an operator session</h1>
              <p>Run this command on the Vxpipe host. It prints a short-lived URL and an 8-digit code.</p>
              <code>mix vxpipe.login</code>
            </div>

            <div :if={@view == :code}>
              <p class="operator-login-label">Verification</p>
              <h1>Enter the 8-digit code</h1>
              <p>The request expires after 10 minutes.</p>
              <form action="/auth/login-token" method="post" class="operator-login-form">
                <input type="hidden" name="_csrf_token" value={@csrf_token} />
                <input type="hidden" name="operator[token]" value={@token} />
                <label for="operator-code">Code</label>
                <input
                  id="operator-code"
                  name="operator[code]"
                  inputmode="numeric"
                  pattern="[0-9]{8}"
                  minlength="8"
                  maxlength="8"
                  autocomplete="one-time-code"
                  autofocus
                  required
                />
                <button type="submit">Continue</button>
              </form>
            </div>

            <div :if={@view == :unavailable} role="alert">
              <p class="operator-login-label">Login unavailable</p>
              <h1>That login request is no longer available.</h1>
              <p>Run <code>mix vxpipe.login</code> again.</p>
              <a href="/auth/login">Back to login</a>
            </div>
          </section>
        </main>
      </body>
    </html>
    """
  end
end
