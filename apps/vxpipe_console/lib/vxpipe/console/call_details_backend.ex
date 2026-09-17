defmodule Vxpipe.Console.CallDetailsBackend do
  @moduledoc false

  alias Vxpipe.Calls.{CallDetailsDocument, CallDetailsRevisionPage, CallReadAccess}

  @callback list(term(), CallReadAccess.authority(), String.t(), keyword()) ::
              {:ok, CallDetailsRevisionPage.t()} | {:error, term()}

  @callback fetch(term(), CallReadAccess.authority(), String.t(), String.t(), keyword()) ::
              {:ok, CallDetailsDocument.t()} | {:error, term()}
end
