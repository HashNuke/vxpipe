defmodule Vxpipe.Console.CallConsolePage do
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
        <link rel="stylesheet" href="/assets/debug_console.css" />
        <title>Call inspection · Vxpipe</title>
      </head>
      <body>
        <div id="call-console-root" data-call-id={@call_id}></div>
        <script type="module" src="/assets/debug_console.js"></script>
      </body>
    </html>
    """
  end
end
