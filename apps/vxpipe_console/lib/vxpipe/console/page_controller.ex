defmodule Vxpipe.Console.PageController do
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
        <title>Vxpipe Console</title>
      </head>
      <body>
        <main><h1>Vxpipe Console</h1></main>
      </body>
    </html>
    """)
  end
end
