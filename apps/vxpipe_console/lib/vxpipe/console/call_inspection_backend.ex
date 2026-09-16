defmodule Vxpipe.Console.CallInspectionBackend do
  @moduledoc "Read boundary used by the Console call-inspection workflow."

  alias Vxpipe.Calls.{
    CallDetailPage,
    CallHistory,
    CallListPage,
    LiveCallInspection,
    PreparedCall,
    Principal,
    UsageReport
  }

  @callback list_calls(term(), Principal.t(), keyword()) ::
              {:ok, CallListPage.t()} | {:error, term()}

  @callback inspect_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, CallDetailPage.t()} | {:error, term()}

  @callback inspect_live_call(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, LiveCallInspection.t()} | {:error, term()}

  @callback fetch_call_history(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, CallHistory.t()} | {:error, term()}

  @callback usage_report(term(), Principal.t(), String.t(), keyword()) ::
              {:ok, UsageReport.t()} | {:error, term()}

  @callback fetch_prepared_call(term(), String.t(), String.t(), keyword()) ::
              {:ok, PreparedCall.t()} | {:error, term()}
end
