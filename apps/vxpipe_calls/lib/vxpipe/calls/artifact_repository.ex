defmodule Vxpipe.Calls.ArtifactRepository do
  @moduledoc "Persistence port for terminal call-artifact metadata."

  alias Vxpipe.Calls.CallArtifact

  @type context :: term()

  @callback store_call_artifact(context(), CallArtifact.t()) ::
              {:ok, CallArtifact.t()} | {:error, term()}

  @callback fetch_call_artifacts(context(), String.t(), String.t()) ::
              {:ok, [CallArtifact.t()]} | {:error, term()}

  @callback fetch_call_artifact(context(), String.t(), String.t(), String.t()) ::
              {:ok, CallArtifact.t()} | {:error, term()}
end
