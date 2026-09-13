defmodule Vxpipe.Console.CallInspectionLayout do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en" phx-socket="/calls/live">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <link rel="icon" href="data:," />
        <link rel="stylesheet" href="/assets/call_inspection.css" />
        <title>Vxpipe Calls</title>
      </head>
      <body class="operator-page">
        {@inner_content}
        <script type="module" src="/assets/live.js"></script>
      </body>
    </html>
    """
  end
end
