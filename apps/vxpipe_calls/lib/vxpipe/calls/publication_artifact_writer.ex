defmodule Vxpipe.Calls.PublicationArtifactWriter do
  @moduledoc "Artifact-write port for one reserved call-details publication."

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication}

  @type context :: term()

  @callback write(context(), CallDetailsPublication.t()) ::
              {:ok, CallDetailsObject.t()} | {:error, term()}
end
