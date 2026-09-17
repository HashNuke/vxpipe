defmodule Vxpipe.Console.ErrorHTML do
  @moduledoc false

  def render("403.html", _assigns), do: "Forbidden"
  def render("404.html", _assigns), do: "Not found"
  def render(_template, _assigns), do: "Request failed"
end
