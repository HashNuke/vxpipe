defmodule Vxpipe.Console.AdminPageController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    csrf_token = Plug.CSRFProtection.get_csrf_token()

    html(
      conn,
      """
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="color-scheme" content="dark" />
          <meta name="csrf-token" content="#{csrf_token}" />
          <link rel="icon" href="data:," />
          <link rel="stylesheet" href="/assets/admin.css" />
          <title>Admin · Vxpipe</title>
        </head>
        <body><div id="admin-root"></div><script type="module" src="/assets/admin.js"></script></body>
      </html>
      """
    )
  end
end
