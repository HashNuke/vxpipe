defmodule Vxpipe.Console.CallInspectionLayout do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Console.CallInspectionAssetController

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
        <link rel="stylesheet" href={CallInspectionAssetController.stylesheet_path()} />
        <title>Vxpipe Calls</title>
      </head>
      <body class="operator-page">
        {@inner_content}
        <script defer src={CallInspectionAssetController.live_path()}></script>
      </body>
    </html>
    """
  end
end
