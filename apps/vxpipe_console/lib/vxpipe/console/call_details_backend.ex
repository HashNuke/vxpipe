defmodule Vxpipe.Console.CallDetailsBackend do
  @moduledoc false

  alias Vxpipe.Calls.{CallDetailsDocument, CallDetailsRevisionPage, Principal}

  @callback list(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, CallDetailsRevisionPage.t()} | {:error, term()}

  @callback fetch(term(), Principal.t(), String.t(), String.t(), keyword()) ::
              {:ok, CallDetailsDocument.t()} | {:error, term()}
end
