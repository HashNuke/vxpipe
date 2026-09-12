defmodule Vxpipe.Calls.PublicationSource do
  @moduledoc "Read port for one call's currently persisted and permitted publication facts."

  alias Vxpipe.Calls.CallDetailsAssessment

  @type context :: term()

  @callback read(context(), String.t(), String.t()) ::
              {:ok, CallDetailsAssessment.t()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :read, 3)
  end

  def valid?(_module), do: false
end
