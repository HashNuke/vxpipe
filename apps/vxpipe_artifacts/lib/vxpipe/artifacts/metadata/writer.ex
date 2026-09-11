defmodule Vxpipe.Artifacts.Metadata.Writer do
  @moduledoc "Persistence boundary for one terminal artifact result."

  alias Vxpipe.Artifacts.Result

  @callback write(keyword(), Result.t()) ::
              :ok | {:retry, term()} | {:discard, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :write, 2)
  end

  def valid?(_module), do: false
end
