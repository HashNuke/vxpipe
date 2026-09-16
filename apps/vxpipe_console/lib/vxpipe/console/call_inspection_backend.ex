defmodule Vxpipe.Console.CallInspectionBackend do
  @moduledoc "Read boundary used by the Console call-inspection workflow."

  alias Vxpipe.Calls.{
    CallDetailPage,
    CallListPage,
    DefinitionRevision,
    LiveCallInspection,
    Principal,
    UsageReport
  }

  @callback list_calls(term(), Principal.t(), keyword()) ::
              {:ok, CallListPage.t()} | {:error, term()}

  @callback inspect_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, CallDetailPage.t()} | {:error, term()}

  @callback inspect_live_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, LiveCallInspection.t()} | {:error, term()}

  @callback usage_report(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, UsageReport.t()} | {:error, term()}

  @callback fetch_definition(term(), String.t(), String.t(), pos_integer(), keyword()) ::
              {:ok, DefinitionRevision.t()} | {:error, term()}
end
