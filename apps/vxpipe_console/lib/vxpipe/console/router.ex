defmodule Vxpipe.Console.Router do
  use Phoenix.Router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :operator do
    plug Vxpipe.Console.OperatorAccess
  end

  scope "/" do
    pipe_through :browser

    get "/", Vxpipe.Console.PageController, :index
  end

  scope "/diagnostics" do
    pipe_through [:operator, :browser]

    get "/", Vxpipe.Console.DiagnosticsController, :index

    live_dashboard "/system",
      live_socket_path: "/diagnostics/live"
  end
end
