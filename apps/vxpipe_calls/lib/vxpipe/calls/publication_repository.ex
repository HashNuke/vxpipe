defmodule Vxpipe.Calls.PublicationRepository do
  @moduledoc "Persistence port for immutable call-details publication revisions."

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication, CallDetailsSnapshot}

  @type context :: term()

  @callback reserve(context(), String.t(), String.t(), CallDetailsSnapshot.t()) ::
              {:ok, CallDetailsPublication.t(), :created | :existing} | {:error, term()}

  @callback mark_published(
              context(),
              String.t(),
              String.t(),
              String.t(),
              CallDetailsObject.t()
            ) :: {:ok, CallDetailsPublication.t()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :reserve, 4) and
      function_exported?(module, :mark_published, 5)
  end

  def valid?(_module), do: false
end
