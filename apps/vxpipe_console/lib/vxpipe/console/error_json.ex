defmodule Vxpipe.Console.ErrorJSON do
  @moduledoc false

  def render("403.json", _assigns), do: %{error: %{code: "forbidden"}}
  def render("404.json", _assigns), do: %{error: %{code: "not_found"}}
  def render(_template, _assigns), do: %{error: %{code: "request_failed"}}
end
