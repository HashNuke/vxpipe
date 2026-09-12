defmodule Vxpipe.Calls.PublicationTimer do
  @moduledoc "Timer boundary used by the post-call publication finalizer."

  @callback schedule(pid(), reference(), non_neg_integer(), term()) :: term()
  @callback cancel(term(), term()) :: :ok

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :schedule, 4) and
      function_exported?(module, :cancel, 2)
  end

  def valid?(_module), do: false
end
