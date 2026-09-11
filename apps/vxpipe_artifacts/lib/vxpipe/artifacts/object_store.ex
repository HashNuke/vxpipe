defmodule Vxpipe.Artifacts.ObjectStore do
  @moduledoc "The streaming object-store boundary used by artifact writers."

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Manifest}

  @type session :: term()
  @type artifact :: map()

  @callback open(ArtifactSpec.t(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback write_chunk(session(), Chunk.t(), keyword()) ::
              {:ok, session()} | {:error, term()}
  @callback complete(session(), Manifest.t(), keyword()) ::
              {:ok, artifact()} | {:error, term()}

  @spec valid?(module()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :open, 2) and
      function_exported?(module, :write_chunk, 3) and
      function_exported?(module, :complete, 3)
  end
end
