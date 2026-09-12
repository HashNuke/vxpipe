defmodule Vxpipe.Artifacts.DocumentObjectStore do
  @moduledoc "Object-store boundary for conditionally writing immutable documents."

  alias Vxpipe.Artifacts.Document

  @callback put(Document.t(), keyword()) :: {:ok, map()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :put, 2)
  end

  def valid?(_module), do: false
end
