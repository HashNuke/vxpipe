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
end
