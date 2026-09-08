defmodule Vxpipe.Console.Router do
  use Phoenix.Router

  get "/", Vxpipe.Console.PageController, :index
end
