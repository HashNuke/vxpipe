defmodule Vxpipe.Console.DiagnosticsLayout do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en" phx-socket="/diagnostics/live">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <link rel="icon" href="data:," />
        <title>Vxpipe diagnostics</title>
        <link rel="stylesheet" href="/assets/diagnostics.css" />
        <script type="module" src="/assets/live.js"></script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
