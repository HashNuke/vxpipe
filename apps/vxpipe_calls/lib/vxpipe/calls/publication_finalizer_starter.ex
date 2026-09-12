defmodule Vxpipe.Calls.PublicationFinalizerStarter do
  @moduledoc "Starts or reuses finalization for one tenant-scoped call."

  @callback start(String.t(), String.t(), keyword()) ::
              {:ok, pid(), :started | :existing} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :start, 3)
  end

  def valid?(_module), do: false
end
