defmodule Vxpipe.Console.CallInspectionBackend do
  @moduledoc "Read boundary used by the Console call-inspection workflow."

  alias Vxpipe.Calls.{CallDetailPage, CallListPage, LiveCallInspection, Principal}

  @callback list_calls(term(), Principal.t(), keyword()) ::
              {:ok, CallListPage.t()} | {:error, term()}

  @callback inspect_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, CallDetailPage.t()} | {:error, term()}

  @callback inspect_live_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, LiveCallInspection.t()} | {:error, term()}
end
