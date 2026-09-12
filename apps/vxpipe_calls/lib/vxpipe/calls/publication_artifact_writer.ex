defmodule Vxpipe.Calls.PublicationArtifactWriter do
  @moduledoc "Artifact-write port for one reserved call-details publication."

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication}

  @type context :: term()

  @callback write(context(), CallDetailsPublication.t()) ::
              {:ok, CallDetailsObject.t()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :write, 2)
  end

  def valid?(_module), do: false
end
