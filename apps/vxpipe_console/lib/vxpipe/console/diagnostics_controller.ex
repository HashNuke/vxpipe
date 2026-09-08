defmodule Vxpipe.Console.DiagnosticsController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="icon" href="data:,">
        <title>Vxpipe diagnostics</title>
      </head>
      <body>
        <main>
          <h1>Vxpipe diagnostics</h1>
          <p>Call measurements will appear here.</p>
          <p><a href="/diagnostics/system">Open system dashboard</a></p>
        </main>
      </body>
    </html>
    """)
  end
end
