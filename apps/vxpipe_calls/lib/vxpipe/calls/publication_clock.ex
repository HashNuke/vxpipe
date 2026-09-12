defmodule Vxpipe.Calls.PublicationClock do
  @moduledoc "Clock boundary used by the post-call publication finalizer."

  @callback now(term()) :: DateTime.t()

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :now, 1)
  end

  def valid?(_module), do: false
end
