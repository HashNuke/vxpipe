defmodule Vxpipe.Calls.CallSpecTemplateFilters do
  @moduledoc "Liquid filters available to call spec templates."

  @doc "Encodes a value as JSON so input text cannot change the rendered document's structure."
  def json(value), do: JSON.encode!(value)
end
