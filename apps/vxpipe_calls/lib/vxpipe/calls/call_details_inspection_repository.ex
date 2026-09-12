defmodule Vxpipe.Calls.CallDetailsInspectionRepository do
  @moduledoc "Read port for tenant-scoped immutable call-details publications."

  alias Vxpipe.Calls.{CallDetailsCursor, CallDetailsDocument, CallDetailsRevision}

  @type context :: term()

  @callback list(context(), String.t(), String.t(), pos_integer(), CallDetailsCursor.t() | nil) ::
              {:ok, [CallDetailsRevision.t()]} | {:error, term()}

  @callback fetch(context(), String.t(), String.t(), String.t()) ::
              {:ok, CallDetailsDocument.t()} | {:error, term()}
end
