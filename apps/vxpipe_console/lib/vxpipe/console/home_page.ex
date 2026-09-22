defmodule Vxpipe.Console.HomePage do
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
        <link rel="stylesheet" href="/assets/home.css" />
        <title>Vxpipe Console</title>
      </head>
      <body>
        <main class="directory-shell">
          <header class="directory-header">
            <h1>Vxpipe Console</h1>
            <p>Available development and operator interfaces.</p>
          </header>

          <nav aria-label="Console interfaces">
            <ul class="surface-list">
              <li>
                <a href="/admin/samples/pipecat-console">
                  <strong>Pipecat console</strong>
                  <span>Create a sample room and exercise the RTVI voice path.</span>
                </a>
              </li>
              <li>
                <a href="/admin/samples/transfer">
                  <strong>Human transfer desk</strong>
                  <span>Join and accept a development human-transfer flow.</span>
                </a>
              </li>
              <li>
                <a href="/auth/login">
                  <strong>Admin</strong>
                  <span>Open the installation operator dashboard.</span>
                </a>
              </li>
              <li>
                <a href="/admin/diagnostics">
                  <strong>Vxpipe diagnostics</strong>
                  <span>Watch bounded gateway and call-engine measurements.</span>
                </a>
              </li>
              <li>
                <a href="/admin/diagnostics/system">
                  <strong>System dashboard</strong>
                  <span>Inspect the running BEAM and OTP system through LiveDashboard.</span>
                </a>
              </li>
            </ul>
          </nav>
        </main>
      </body>
    </html>
    """
  end
end
